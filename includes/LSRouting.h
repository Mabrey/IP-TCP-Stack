#ifndef LSROUTING_H
#define LSROUTING_H

#define MAXVALUE 255

typedef struct lspIndex
{
    uint8_t dest;
    uint8_t hopTo;
    uint8_t hopCost;
}lspIndex;

typedef struct routingTable
{
    lspIndex lspIndex[20];      //assuming only around 20 nodes or less
   // uint8_t tableCount;
}routingTable;

//set all index hopCost to -1 to show no connection
void initializeTable(routingTable* table)
{
    int i;
    for (i = 0; i < 20; i++)
    {
        table->lspIndex[i].hopCost = 0;
    }
   // table->tableCount = 0;
}

//check if tablecount is less than max node count (20), then push incoming index value to back of current table
void tablePush(routingTable* table, lspIndex ind)
{	
    table -> lspIndex[ind.dest] = ind;
}

//retrieve the index if it has the same name as nodeID, else return blank index
lspIndex getTableIndex(routingTable* table, int nodeID)
{
    uint8_t i;
    lspIndex getIndex; 
    for (i = 0; i < 20; i++)
    {
        if(table -> lspIndex[i].dest == nodeID)
            getIndex = table -> lspIndex[i];   
    }
    return getIndex;
}

//if cost of hop is less than the current cost, update the table with incoming index 
bool updateTableCost(routingTable* table, lspIndex ind)
{
    
    if(table -> lspIndex[ind.dest].hopCost > ind.hopCost )
    {
        //ind.hopCost = hopCost;
        table -> lspIndex[ind.dest] = ind; 
        return TRUE;
    }
    
    return FALSE;
}

//if nodeID exists, remove it from the table and return it
lspIndex popTableIndex(routingTable* table, int nodeID)
{
    int i;
    lspIndex pop;

    if (table -> lspIndex[nodeID].hopCost != 255 && table -> lspIndex[nodeID].hopCost != 0)
    {
      
        //store index in pop, store the last index of the table into lspIndex[i], then make the tablecount smaller to make the table smaller
        pop = table -> lspIndex[nodeID];
        table -> lspIndex[nodeID].hopCost = 255;
        table -> lspIndex[nodeID].hopTo = 0;
        return pop;
    }
    return pop;
}

//pop the index with the lowest cost, used in our tentative list for dijkstra's alg
lspIndex popMinCostIndex(routingTable* tentative)
{
    int i;
    int min;
    lspIndex minIndex;
    minIndex.hopCost = MAXVALUE;
    for (i = 0; i < 20; i++)
    {
        if( ((tentative -> lspIndex[i].hopCost) < minIndex.hopCost) && (tentative -> lspIndex[i].hopCost != 0) )
        {
            min = i;
            minIndex = tentative -> lspIndex[i];
        }
    }
    minIndex = popTableIndex(tentative, min);
    return minIndex;
}

//pass in a destination to find the next nodeID to hop to
int findNextHop(routingTable* table, int dest)
{
    return table -> lspIndex[dest].hopTo;
}
/*
//does the table's index's destination match the incoming index's destination
bool doesTableDestMatch(routingTable* table, lspIndex ind)
{
    uint8_t i;
    for (i = 0; i < table -> tableCount; i++)
    {
        if(table -> lspIndex[i].dest == ind.dest )
            return TRUE;
    }
    return FALSE;
}
*/
//check if table is empty
bool isTableEmpty(routingTable* table)
{
    int i;
    int count = 0;
    for(i = 1; i < 20; i++)
    {
        if (table->lspIndex[i].hopCost == 0 || table->lspIndex[i].hopCost == 255)
            count++;
        if (count == 19)
            return TRUE;
    }
    return FALSE;
}

//does the table contain the node
bool doesTableContain(routingTable* table, int nodeID)
{
    if(table -> lspIndex[nodeID].hopCost != 255 && table -> lspIndex[nodeID].hopCost != 0)
         return TRUE;
    
    return FALSE;
}

#endif
