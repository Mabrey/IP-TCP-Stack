/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"

typedef struct neighbor                 //create neighbor struct 
{				
	uint8_t node;
	uint8_t age;
    bool inList;
} neighbor;

typedef struct neighborhood
{
    neighbor neighbor[20];
    int size;
}neighborhood;


module Node{
   uses interface Boot;
   uses interface SplitControl as AMControl;
   uses interface Receive;
   uses interface SimpleSend as Sender;
   uses interface CommandHandler;
   //uses interface List<neighbor*> as neighborList;			//tracks neighbors
   uses interface List<pack> as packList;					//tracks seen and sent packets
  // uses interface Pool<neighbor> as neighborPool;
   uses interface Timer<TMilli> as NodeTimer;
   uses interface Random as Random;
}

implementation{
   pack sendPackage;
   uint16_t seqCount = 0;
   neighborhood neighborList;

   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
   void pushPackList(pack package);
   bool packMatch(pack *package);
   void findNeighbors();
   void initNeighborList();
   void printNeighbor();
   bool containNeighbor(int node);

   event void Boot.booted(){
        //dbg(GENERAL_CHANNEL, "Booted\n");
        uint16_t start;
        call AMControl.start();

        start = TOS_NODE_ID*2000;  
        call NodeTimer.startOneShot(start);
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS)
      {
         //dbg(GENERAL_CHANNEL, "Radio On\n");
         initNeighborList();
      }
      else
      {
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}
   event void NodeTimer.fired(){
       findNeighbors();
       call NodeTimer.startPeriodic(2000000);
   }

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
        pack* myMsg=(pack*) payload;
        //dbg("neighbor", "Packet Received from %d\n", myMsg->src);
        if(len==sizeof(pack))
        {
            // neighbor* Neighbor, *neighbor_ptr;
             //check if packet is expired or if we've already seen it.
		    if (myMsg->TTL != 0 && !packMatch(myMsg))									 
		    {	
                //since we didnt match before, add it to list
                makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL, myMsg->protocol, myMsg->seq, (uint8_t*) myMsg->payload, sizeof(myMsg->payload));
                pushPackList(sendPackage);							
		        //dbg("neighbor", "Packet Already seen/dead\n");  
                //if using AMBA, then neighbor is broadcasting to all neighbors
                if (myMsg->dest == AM_BROADCAST_ADDR)      
                {
                    //dbg("neighbor", "Packet Received from %d\n", myMsg->src);
                    //logPack(myMsg);
                    //if broadcast was ping, neighbor is trying to search for new neighbors or keep in touch with old ones.
                    //send them a reply to add you to their list
                    if (myMsg->protocol == PROTOCOL_PING)      
                    {
                        makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 1, PROTOCOL_PINGREPLY, myMsg->seq, (uint8_t*) myMsg->payload, sizeof(myMsg->payload));                     
                        pushPackList(sendPackage);
                        seqCount++;
                        dbg("neighbor", "Sending Ping Reply to %d\n", myMsg -> src);
                        call Sender.send(sendPackage,myMsg->src);   //send back to source
                    }

                    //if broadcast was ping reply, neighbor is updating their existance.
                    else if (myMsg->protocol == PROTOCOL_PINGREPLY)     
                    {                                                    
                        dbg("neighbor", "Ping Reply from %d\n", myMsg -> src);

                        //if we've seen this neighbor before, reset their age
                        if(containNeighbor(myMsg->src))       
                        {    
                                neighborList.neighbor[myMsg->src].age = 0;
                                dbg("neighbor", "I know this neighbor\n");
                        }    

                        //if you dont recognize the neighbor, add them to the list.
                        else                  
                        {
                            dbg("general", "Neighbor %d added to list\n", myMsg -> src);
                            neighborList.neighbor[myMsg->src].age = 0;
                            neighborList.neighbor[myMsg->src].node = myMsg-> src;
                            neighborList.neighbor[myMsg->src].inList = TRUE;
                            neighborList.size += 1;
                    
                            //printNeighbor();
                        }

                    }
                }
                else if (myMsg->dest == TOS_NODE_ID)        //the destination of the packet matches you, NOT DISCOVERY!
                {                                          
                    if (myMsg->protocol == PROTOCOL_PING)     //if message was ping, the source wants a reply
                    {
                    dbg("flooding", "Packet has arrived to final destination. Current Node: %d, Source Node: %d, Packet Message: %s\n", TOS_NODE_ID, myMsg->src, myMsg->payload);

                        //make reply packet back to the source
                        makePack(&sendPackage, TOS_NODE_ID, myMsg->src, 32, PROTOCOL_PINGREPLY, seqCount, (uint8_t*) myMsg->payload, sizeof(myMsg->payload));
                        pushPackList(sendPackage);
                        seqCount++;
                        call Sender.send(sendPackage, AM_BROADCAST_ADDR);
                    }
                    else if (myMsg->protocol == PROTOCOL_PINGREPLY)   
                    {  //if message was a reply, you pinged it and recieved the ack.
                        dbg("flooding", "Packet reply recieved! Current Node: %d, Source Node: %d, Packet Message: %s\n", TOS_NODE_ID, myMsg->src, myMsg->payload);
                        //save the packet 
                        makePack(&sendPackage, myMsg->src, TOS_NODE_ID, myMsg->TTL, myMsg->protocol, myMsg->seq, (uint8_t*) myMsg->payload, sizeof(myMsg->payload));
                        pushPackList(sendPackage);               
                    }
                }
    
                else //packet isn't yours, pass it along
                {
                    dbg("flooding", "Passing message from %d meant for %d\n", myMsg->src, myMsg->dest);
                    makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1, myMsg->protocol, myMsg->seq, (uint8_t*) myMsg->payload, sizeof(myMsg->payload));
                    pushPackList(sendPackage);
                    call Sender.send(sendPackage, AM_BROADCAST_ADDR);
                }   
                return msg;
            }
            return msg;
        }
        else
        {
            dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
            return msg;
        }
   
    }    
           

   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      makePack(&sendPackage, TOS_NODE_ID, destination, 64, PROTOCOL_PING, seqCount, payload, PACKET_MAX_PAYLOAD_SIZE);
      seqCount++;
      logPack(&sendPackage);
      pushPackList(sendPackage);
      call Sender.send(sendPackage, AM_BROADCAST_ADDR);
   }

   event void CommandHandler.printNeighbors(){
      printNeighbor();
   }

   event void CommandHandler.printRouteTable(){}

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){}

   event void CommandHandler.setTestClient(){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }

   void pushPackList(pack Package) 
    {
        if(call packList.isFull())          //added check full to limit total packets held onto, and make sure enough space is allocated before pushing new packet on list
        {
            //dbg("general", "list is full\n");
            call packList.popfront();
        }
        call packList.pushback(Package);
       
    }

    bool packMatch(pack *packet)		//test if packet matches src
    {
		nx_uint8_t i, size;
		pack seenPacket;                //create packet to pull from list
		size = call packList.size();

		if (size == 0) {}
			//dbg(GENERAL_CHANNEL, "No packets in list\n");     //if no packets in list, no need to compare. It's a new packet, return false
	
		else 
		{
			for(i = 0; i < size; i++)               //iterate through packList, compare source, destination, and the sequence number.
			{
				seenPacket = call packList.get(i);
				if (seenPacket.src == packet->src && 
					seenPacket.dest == packet->dest &&
					seenPacket.seq == packet->seq &&
                    seenPacket.protocol == packet->protocol)
                    //dbg("general", "packet match\n");
					return TRUE;                            //if packet is a match, return true
			}
		}
		return FALSE;
	}

    void findNeighbors()					//look for neighbor nodes
    {
        char* message = "Hey!\n";
        int i;
        if (neighborList.size > 0)       //first check the list isn't empty
        {
            for (i = 0; i < 20; i++)      //update the age of the neighbors
            {   
                if (neighborList.neighbor[i].inList == TRUE)          
                { 
                    neighborList.neighbor[i].age += 1;      //add one to age
                    if (neighborList.neighbor[i].age > 5)        //if older than 10, remove from list
                    {
                        neighborList.neighbor[i].age = 0;
                        neighborList.neighbor[i].node = 0;
                        neighborList.size -= 1;
                    }
                }
            }
         }
     
                            //create a package to get ready to send for neighbor discovery
        makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 2, PROTOCOL_PING, seqCount, (uint8_t*) message, (uint8_t) sizeof(message));
        pushPackList(sendPackage);
        seqCount++;
        call Sender.send(sendPackage, AM_BROADCAST_ADDR);
    }

    void initNeighborList()
    {
        int i;
        for(i = 0; i < 20; i++)
        {
            neighborList.neighbor[i].node = -1;
            neighborList.neighbor[i].age = -1;
            neighborList.neighbor[i].inList = FALSE;
        }
        neighborList.size = 0;
    }

    void printNeighbor()
   {
		int i;
        if (neighborList.size == 0)
        {
            dbg(GENERAL_CHANNEL, "No Neighbors\n");
            return;
        }

        for(i = 0; i < 20; i++)
        {
            if (neighborList.neighbor[i].inList)
                dbg(GENERAL_CHANNEL, "Node: %d, Neighbor: %d, Neighbor Age: %d\n", TOS_NODE_ID, neighborList.neighbor[i].node, neighborList.neighbor[i].age);
        }
        return;
   }

    bool containNeighbor(int node)
    {
        return neighborList.neighbor[node].inList;
    }
}
