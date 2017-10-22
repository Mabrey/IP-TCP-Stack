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
} neighbor;

module Node{
   uses interface Boot;
   uses interface SplitControl as AMControl;
   uses interface Receive;
   uses interface SimpleSend as Sender;
   uses interface CommandHandler;
   uses interface List<neighbor*> as neighborList;			//tracks neighbors
   uses interface List<pack> as packList;					//tracks seen and sent packets
   uses interface Pool<neighbor> as neighborPool;
   uses interface Timer<TMilli> as NodeTimer;
   uses interface Random as Random;
}

implementation{
   pack sendPackage;
   uint16_t seqCount = 0;

   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
   void pushPackList(pack package);
   bool packMatch(pack *package);
   void findNeighbors();
   void printNeighbor();

   event void Boot.booted(){
       uint16_t seed, start;
      call AMControl.start();

        start = call Random.rand16()%1000;  
        seed = call Random.rand16()%1500 + start;
      
      dbg(GENERAL_CHANNEL, "Booted\n");
   
       call NodeTimer.startPeriodicAt(start, seed+10000);
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}
   event void NodeTimer.fired(){
       findNeighbors();
   }

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
        if(len==sizeof(pack))
        {
             pack* myMsg=(pack*) payload;												//payload becomes MyMsg
             neighbor* Neighbor, *neighbor_ptr;

		    if (myMsg->TTL != 0 && !packMatch(myMsg))									//check if packet is expired or if we've already seen it. 
		    {								
		    //dbg("neighbor", "Packet Already seen/dead\n");  //if packet is expired or already seen, we can drop it.
                if (myMsg->dest == AM_BROADCAST_ADDR)      //if using AMBA, then neighbor is broadcasting to all neighbors
                {
                    dbg("neighbor", "Packet Received from %d\n", myMsg->src);
                    logPack(myMsg);
                    makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL, myMsg->protocol, myMsg->seq, (uint8_t*) myMsg->payload, sizeof(myMsg->payload));
                    pushPackList(sendPackage);

                    if (myMsg->protocol == PROTOCOL_PING)       //if broadcast was ping, neighbor is trying to search for new neighbors or keep in touch with old ones.
                    {
                        makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, myMsg->TTL - 1, PROTOCOL_PINGREPLY, myMsg->seq, (uint8_t*) myMsg->payload, sizeof(myMsg->payload));
                        pushPackList(sendPackage);
                        dbg("neighbor", "Sending packet reply to %d\n", myMsg -> src);
                        call Sender.send(sendPackage,myMsg->src);   //send back to source
                    }

                    else if (myMsg->protocol == PROTOCOL_PINGREPLY)      //if broadcast was ping reply, neighbor is updating their existance.
                    {                                                      //Check if they are in your neighbor list and set age to Zero.
                        bool Neighbor_in_List;
                        uint8_t size, i;
                        
                        Neighbor_in_List = FALSE;                       //assume you don't know this neighbor
                        size = call neighborList.size();

                        for (i = 0; i < size; i++)                      //check all neighbors in your list for a match
                        {
                            neighbor_ptr = call neighborList.get(i);
                            
                            if(neighbor_ptr-> node == myMsg->src)       //if they match, set bool to true and update age
                            {
                                neighbor_ptr -> age = 0;
                                Neighbor_in_List = TRUE;
                                dbg("neighbor", "I know this neighbor");
                            }
                        } 

                        if(Neighbor_in_List == FALSE)                   //if you dont recognize the neighbor, add them to the list.
                        {
                            dbg("general", "Neighbor added to list\n");
                            dbg("general", "Source: %d\n", myMsg->src);
                            Neighbor = call neighborPool.get();
                            Neighbor->node = myMsg->src;
                            Neighbor-> age = 0;
                            call neighborList.pushback(Neighbor);
                            printNeighbor();
                        }

                    }
                }
                else if (myMsg->dest == TOS_NODE_ID)        //the destination of the packet matches you
                {                                          
                    if (myMsg->protocol == PROTOCOL_PING)     //if message was ping, the source wants a reply
                    {
                    dbg("flooding", "Packet has arrived to final destination. Current Node: %d, Source Node: %d \nPacket Message: %d\n", TOS_NODE_ID, myMsg->src, myMsg->payload);

                        //save the packet 
                        makePack(&sendPackage, myMsg->src, TOS_NODE_ID, myMsg->TTL-1, myMsg->protocol, myMsg->seq, (uint8_t*) myMsg->payload, sizeof(myMsg->payload));
                        pushPackList(sendPackage);

                        //make reply packet back to the source
                        makePack(&sendPackage, TOS_NODE_ID, myMsg->src, 255, PROTOCOL_PINGREPLY, seqCount, (uint8_t*) myMsg->payload, sizeof(myMsg->payload));
                        seqCount++;
                        pushPackList(sendPackage);
                        call Sender.send(sendPackage, AM_BROADCAST_ADDR);
                    }
                    else if (myMsg->protocol == PROTOCOL_PINGREPLY)   
                    {  //if message was a reply, you pinged it and recieved the ack.
                        dbg("flooding", "Packet reply recieved! Current Node: %d, Source Node: %d \nPacket Message: %d\n", TOS_NODE_ID, myMsg->src, myMsg->payload);

                            //save the packet 
                        makePack(&sendPackage, myMsg->src, TOS_NODE_ID, myMsg->TTL-1, myMsg->protocol, myMsg->seq, (uint8_t*) myMsg->payload, sizeof(myMsg->payload));
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

   event void CommandHandler.printNeighbors(){}

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
					seenPacket.seq == packet->seq)
                    //dbg("general", "packet match\n");
					return TRUE;                            //if packet is a match, return true
			}
		}
		return FALSE;
	}

    void findNeighbors()					//look for neighbor nodes
    {
        char* message = "Hey!\n";

        if (call neighborList.isEmpty() == FALSE)       //first check the list isn't empty
        {
            uint8_t size, age, i;
            neighbor* neighbor_prt, *neighborRemoved;  
            size = call neighborList.size();

            for (i = 0; i < size; i++)      //update the age of the neighbors
            {             
                neighbor_prt = call neighborList.get(i);
                neighbor_prt->age += 1;      //add one to age
                if (neighbor_prt->age > 10)        //if older than 10, remove from list
                {
                    neighborRemoved = call neighborList.remove(i);
                    call neighborPool.put(neighborRemoved);
                    i--;
                    size--;
                }
            }
         }
     
                            //create a package to get ready to send for neighbor discovery
        makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 2, PROTOCOL_PING, 0, (uint8_t*) message, (uint8_t) sizeof(message));
        pushPackList(sendPackage);
        call Sender.send(sendPackage, AM_BROADCAST_ADDR);
    }

    void printNeighbor()
   {
		nx_uint8_t size, i; 
		size = call neighborList.size();

	   if(call neighborList.isEmpty() == FALSE)			//check neighbor list isnt empty
		{
			for (i = 0; i < size; i++)
			{
				neighbor* neighbor_prt = call neighborList.get(i);
				dbg(GENERAL_CHANNEL, "Node: %d, Neighbor: %d, Neighbor Age: %d\n", TOS_NODE_ID, neighbor_prt->node, neighbor_prt->age);		
			}
		}
		else dbg(GENERAL_CHANNEL, "No Neighbors\n");
   
   }
}
