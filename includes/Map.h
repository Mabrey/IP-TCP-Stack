#ifndef MAP_H
#define MAP_H

#define MAPSIZE 20

typedef struct map{
    uint8_t hopCost[MAPSIZE];
} map;

void initializeMap(map* costMap, int nodeID){
    int i;
    for(i = 0; i < MAPSIZE; i++)
        costMap[nodeID].hopCost[i] = -1;    
}

#endif