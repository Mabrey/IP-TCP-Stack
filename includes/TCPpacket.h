#ifndef TCPPACKET_H
#define TCPPACKET_H

#include "packet.h"


enum{
	HEADER_LENGTH = 8,
	TCPPACKET_MAX_PAYLOAD_SIZE = PACKET_MAX_PAYLOAD_SIZE - HEADER_LENGTH,
};


typedef struct TCPpack{
	uint8_t srcPort;
	uint8_t destPort;
	uint16_t seq;		
	uint8_t flag;		
	uint8_t window;
	uint16_t payload[TCPPACKET_MAX_PAYLOAD_SIZE/2];
}TCPpack;

#endif
