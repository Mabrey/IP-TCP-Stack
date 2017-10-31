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
#include "includes/Map.h"
#include "includes/LSRouting.h"

//create neighbor struct 
typedef struct neighbor                 
{				
	uint8_t node;
	uint8_t age;
    bool inList;
} neighbor;

//struct to keep track of neighbors
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
   uses interface List<pack> as packList;					
   uses interface Timer<TMilli> as NodeTimer;
   uses interface Timer<TMilli> as LSPNodeTimer;
   uses interface Timer<TMilli> as dijkstraTimer;
   uses interface Random as Random;
}

implementation{
        
    //Project 1     
    pack sendPackage;
    uint16_t seqCount = 0;
    neighborhood neighborList;

    //Project 2
    map Map[20];
    uint8_t cost[20];
    int sizeOfNetwork;
    routingTable confirmedTable;
    routingTable tentativeTable;
    bool nodeFired = FALSE;
    bool LSPFired = FALSE;

    // Packet handling
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
    void pushPackList(pack package);
    bool packMatch(pack *package);

    //Neighbor discovery
    void findNeighbors();
    void initNeighborList();
    bool printNeighbor();
    bool containNeighbor(int node);

    //Routing 
    void printMap();
    void printCost(int node);
    void lspShareNeighbor();
    void dijkstra();
    int findForwardDest(int dest);
    int detectNetworkSize();

    event void Boot.booted(){
        //dbg(GENERAL_CHANNEL, "Booted\n");
        uint16_t start, lspStart, dijkstraStart;
        call AMControl.start();
         initializeMap(Map);

        start = TOS_NODE_ID*2000; 
        lspStart = TOS_NODE_ID*50000; 
        dijkstraStart = TOS_NODE_ID * 1000000;
        call NodeTimer.startOneShot(start);
        call LSPNodeTimer.startOneShot(lspStart);
        call dijkstraTimer.startOneShot(dijkstraStart);
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
       nodeFired = TRUE;
       call NodeTimer.startPeriodic(500000);
   }

    event void LSPNodeTimer.fired(){
        if (nodeFired)
        {
            lspShareNeighbor();
            LSPFired = TRUE;
        }
        
        
        call LSPNodeTimer.startPeriodic(500000);
    }

    event void dijkstraTimer.fired(){
        if (LSPFired)
        {
            dbg(GENERAL_CHANNEL, "Size of Network: %d\n", detectNetworkSize());
            dbg(GENERAL_CHANNEL, "Firing DIJKSTRA TIMER\n");
            dijkstra(); 
        }
       // dbg(GENERAL_CHANNEL, "Firing DIJKSTRA TIMER\n");
        call dijkstraTimer.startPeriodic(1000000);
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
                    
                    //if broadcast was protocol_lsp, save the cost of node and pass it on
                    else if (myMsg -> protocol == PROTOCOL_LSP)
                    {
                        int i;
                       // dbg(GENERAL_CHANNEL, "updating cost map\n");

                        for (i = 1; i < 20; i++) {  
                            if(myMsg->payload[i] > 0 && myMsg->payload[i] != 255)
                                Map[myMsg->src].hopCost[i] = myMsg->payload[i];
                           // dbg(GENERAL_CHANNEL, "Payload: %d , Map hopcost for %d: %d, i = %d\n", myMsg->payload[i], myMsg->src, Map[myMsg->src].hopCost[i], i );
                        }
                        makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1, myMsg->protocol, myMsg->seq, (uint8_t*) myMsg->payload, sizeof(myMsg->payload));
                        pushPackList(sendPackage);
                        //printCost();
                        //printMap();
                        call Sender.send(sendPackage, AM_BROADCAST_ADDR);
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
                    int dest = myMsg->dest;
                    dest = findForwardDest(dest);
                    if (dest == 0)
                    {
                        dbg(GENERAL_CHANNEL, "No destination to pass to, must drop");
                        return msg;
                    }
                    dbg("flooding", "Passing message from %d meant for %d\n", myMsg->src, myMsg->dest);
                    makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1, myMsg->protocol, myMsg->seq, (uint8_t*) myMsg->payload, sizeof(myMsg->payload));
                    pushPackList(sendPackage);
                    call Sender.send(sendPackage, dest);
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
        int dest;
        dest = findForwardDest(destination);
        dbg(GENERAL_CHANNEL, "PING EVENT \n");
        makePack(&sendPackage, TOS_NODE_ID, destination, 64, PROTOCOL_PING, seqCount, payload, PACKET_MAX_PAYLOAD_SIZE);
        seqCount++;
        logPack(&sendPackage);
        pushPackList(sendPackage);

        call Sender.send(sendPackage, dest);
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

    bool printNeighbor()
   {
		int i;
        if (neighborList.size == 0)
        {
            dbg(GENERAL_CHANNEL, "No Neighbors\n");
            return FALSE;
        }

        for(i = 0; i < 20; i++)
        {
            if (neighborList.neighbor[i].inList)
                dbg(GENERAL_CHANNEL, "Node: %d, Neighbor: %d, Neighbor Age: %d, i = %d\n", TOS_NODE_ID, neighborList.neighbor[i].node, neighborList.neighbor[i].age, i);
        }
        return TRUE;
   }

    bool containNeighbor(int node)
    {
        return neighborList.neighbor[node].inList;
    }

    void printMap()
    {
        int i, j;
        dbg(GENERAL_CHANNEL, "Printing Map\n");
        for (i = 1; i < 20; i++)
        {
            for (j = 1; j < 20; j++)
            {
                //if(Map[i].hopCost[j] > 0)
                    dbg(GENERAL_CHANNEL, "Src: %d, Dest: %d, Cost:%d\n", i, j, Map[i].hopCost[j]);
            }
        }
    }

    void printCost(int node)
    {
        int i;
        dbg(GENERAL_CHANNEL, "Printing Cost List\n");
        for (i = 1; i < 20; i++)
            {
                if(cost[i] > 0 && cost[i] != 255)
                    dbg(GENERAL_CHANNEL, "Src: %d, Dest: %d, Cost:%d\n", node, i, cost[i]);
            }
    }

    void printTable()
    {
        int i;
        dbg(GENERAL_CHANNEL, "Printing Table\n");
        for (i = 1; i < 20; i++)
        {
            dbg(GENERAL_CHANNEL, "Dest: %d, HopTo: %d, Cost:%d\n", confirmedTable.lspIndex[i].dest, confirmedTable.lspIndex[i].hopTo, confirmedTable.lspIndex[i].hopCost);  
        }           
    }

    void lspShareNeighbor()
    {
        int i;
        //initialize cost list
        for(i = 0; i < 20; i++)
            cost[i] = -1;
        
        for(i = 1; i < 20; i++)
        {
            if(neighborList.neighbor[i].inList == TRUE)
            {
                cost[i] = 1;
                Map[TOS_NODE_ID].hopCost[i] = 1;
            }
            else if(i == TOS_NODE_ID)
            {
                cost[i] = 0;
                Map[TOS_NODE_ID].hopCost[i] = 0;
            }
        }
        if (printNeighbor())
        {
            printCost(TOS_NODE_ID);
                            //create a package to get ready to send for neighbor discovery
            makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 32, PROTOCOL_LSP, seqCount, (uint8_t*) cost, (uint8_t) sizeof(cost));
            pushPackList(sendPackage);
            seqCount++;
            call Sender.send(sendPackage, AM_BROADCAST_ADDR);
        }
        
    }

    void dijkstra()
    {
        
        int i;
        bool tentIsEmpty = FALSE;
        lspIndex Next, Temp;
        printMap();
        initializeTable(&confirmedTable);
        initializeTable(&tentativeTable);

        Next.dest = TOS_NODE_ID;
        Next.hopTo = TOS_NODE_ID;
        Next.hopCost = 0;
        tablePush(&confirmedTable, Next);
        /*
        confirmedTable.lspIndex[TOS_NODE_ID].dest = TOS_NODE_ID;
        confirmedTable.lspIndex[TOS_NODE_ID].hopTo = TOS_NODE_ID;
        confirmedTable.lspIndex[TOS_NODE_ID].hopCost = 0;
        Next = confirmedTable.lspIndex[TOS_NODE_ID];
        */
        //make next equal to current node, and expand its neighbors onto tentative list
        
        do
        {
            for (i = 1; i < 20; i++)
            {
                if (Map[Next.dest].hopCost[i] == 1 && i != TOS_NODE_ID)
                {
                    Temp.dest = i;

                    if (Next.dest == TOS_NODE_ID)
                        Temp.hopTo = Temp.dest;
                    
                    else 
                        Temp.hopTo = Next.hopTo;
                    //if (Map[Next.dest].hopCost[i] == 1)
                    //    Temp.hopTo = i;
                    //else Temp.hopTo = Next.hopTo;
                    Temp.hopCost = Next.hopCost + 1;   
                    
                   
                    if(!doesTableContain(&confirmedTable,Temp.dest))
                    {
                        if(!doesTableContain(&tentativeTable, Temp.dest))
                            tablePush(&tentativeTable, Temp);
                        
                        else 
                        {
                            if (getTableIndex(&tentativeTable, Temp.dest).hopCost > Temp.hopCost)
                                updateTableCost(&tentativeTable, Temp );
                        }  
                    }
                }
            }

            if (isTableEmpty(&tentativeTable))
                tentIsEmpty = TRUE;

            else
            {
                Next = popMinCostIndex(&tentativeTable);
                tablePush(&confirmedTable, Next);
            }
            

        } while(!tentIsEmpty);

        printTable();
    }

    int findForwardDest(int dest)
    {
        int forward;
        forward = getTableIndex(&confirmedTable, dest).hopTo;   
        return forward;  
    }

    int detectNetworkSize()
    {
        int i, j, networkSize;
        networkSize = 0;

        for (i = 1; i < 20; i++)
        {
            for(j = 1; j < 20; j++)
            {
                 if (Map[i].hopCost[j] == 1)
                 {
                     networkSize++;
                     break;
                 } 
            }
        }
        return networkSize;
    }

}
