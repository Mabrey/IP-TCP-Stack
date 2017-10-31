#ifndef MAP_H
#define MAP_H

#define MAPSIZE 20

typedef struct map{
    uint8_t hopCost[MAPSIZE];
} map;

void initializeMap(map* costMap){
    int i, j;
    for(i = 0; i < MAPSIZE; i++)
    {
        for (j = 0; j <MAPSIZE; j++)
        {
            if (i == j)
                costMap[i].hopCost[j] = 0;
            else
                costMap[i].hopCost[j] = 255;    
        }
    }
}

#endif