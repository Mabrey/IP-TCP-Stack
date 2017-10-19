#ifndef LSROUTING_H
#define LSROUTING_H

typedef struct TableIndex{
    uint8_t dest;
    uint8_t nextHop;
    uint8_t hopCost;
}TableIndex;

