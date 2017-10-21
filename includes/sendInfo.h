//Author: UCM ANDES Lab
//Date: 2/15/2012
#ifndef PACK_BUFFER_H
#define PACK_BUFFER_H

#include "packet.h"

enum{
	SEND_BUFFER_SIZE=128
};

typedef struct sendInfo{
	pack packet;
	uint16_t src;
	uint16_t dest;
}sendInfo;

typedef struct sendBuffer{
	sendInfo buffer[SEND_BUFFER_SIZE];
	uint8_t size;
}sendBuffer;

void sendBufferInit(sendBuffer *buffer){
	buffer->size=0;
}

sendInfo sendBufferPopFront(sendBuffer *buffer){
	int i;
	sendInfo returnVal;
	
	returnVal = buffer->buffer[0];
	for(i=0; i < buffer->size-1; i++){
		buffer->buffer[i]=buffer->buffer[i+1];
	}
	
	buffer->size--;
	return returnVal;
}

void sendBufferPushBack(sendBuffer *buff, pack packet, uint16_t src, uint16_t dest){
	sendInfo info;
	info.packet=packet;
	info.src = src;
	info.dest = dest;
	
	buff->buffer[buff->size] = info;
	buff->size++;
}

#endif /* PACK_BUFFER_H */
