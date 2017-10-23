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
    uint8_t tableCount;
}routingTable;

//set all index hopCost to -1 to show no connection
void initializeTable(routingTable* table)
{
    int i;
    for (i = 0; i < 20; i++)
    {
        table->lspIndex[i].hopCost = -1;
    }
    table->tableCount = 0;
}

//check if tablecount is less than max node count (20), then push incoming index value to back of current table
bool tablePushBack(routingTable* table, lspIndex ind)
{	
    if(table->tableCount != 20){
        table->lspIndex[table -> tableCount] = ind;
        table->tableCount++;
        return TRUE;
    }
    return FALSE;
}

//retrieve the index if it has the same name as nodeID, else return blank index
lspIndex getTableIndex(routingTable* table, int nodeID)
{
    uint8_t i;
    lspIndex getIndex; 
    for (i = 0; i < table -> tableCount; i++)
    {
        if(table -> lspIndex[i].dest == nodeID)
            getIndex = table -> lspIndex[i];   
    }
    return getIndex;
}

//if cost of hop is less than the current cost, update the table with incoming index 
bool updateTableCost(routingTable* table, lspIndex ind, int hopCost)
{
    int i;
    for(i = 0; i < table -> tableCount; i++)
    {
        if(table -> lspIndex[i].hopCost > hopCost && table -> lspIndex[i].dest == ind.dest)
        {
            //ind.hopCost = hopCost;
            table -> lspIndex[i] = ind; 
            return TRUE;
        }
    }
    return FALSE;
}

//if nodeID exists, remove it from the table and return it
lspIndex popTableIndex(routingTable* table, int nodeID)
{
    int i;
    lspIndex pop;
    for(i = 0; i < table -> tableCount; i++)
    {
        if (i == nodeID) 
        {
            if(table -> tableCount > 1)     //if node matches i, and table isnt smaller than single element, remove the element
            {
                //store index in pop, store the last index of the table into lspIndex[i], then make the tablecount smaller to make the table smaller
                pop = table -> lspIndex[i];
                table -> lspIndex[i] = table -> lspIndex[table -> tableCount - 1];
                table -> tableCount = table -> tableCount - 1;
                i--;
                return pop;
            }
            else
                table -> tableCount = 0; //make sure tableCount doesnt go negative       
        }
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
    for (i = 0; i < tentative -> tableCount; i++)
    {
        if(tentative -> lspIndex[i].hopCost < minIndex.hopCost)
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
    int i; 
    for (i = 0; i < table -> tableCount; i++)
    {
        if(table -> lspIndex[i].dest == dest)
            return table -> lspIndex[i].hopTo;
    }
}
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

//check if table is empty
bool isTableEmpty(routingTable* table)
{
    if (table->tableCount == 0)
        return TRUE;

    return FALSE;
}

//does the table contain the node
bool doesTableContain(routingTable* table, int nodeID)
{
    uint8_t i;
    for (i = 0; i < table -> tableCount; i++)
    {
        if(table -> lspIndex[i].dest == nodeID )
            return TRUE;
    }
    return FALSE;
}

#endif
