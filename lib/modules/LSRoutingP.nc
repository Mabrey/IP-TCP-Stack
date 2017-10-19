typedef struct neighbor                 //create neighbor struct 
{				
	uint8_t node;
	uint8_t age;
    uint8_t cost;
} neighbor;


typedef struct LSP
{
    uint16_t TOS_NODE_ID;
    List<neighbor> neighborList;
    uint8_t seqNum;
    uint8_t maxTTL;
}LSP;

generic module LSRoutingP()
{
    command void initializeMap();
    command void initializeLSTable(); 
}

implementation
{
    
}
