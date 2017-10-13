//Author: UCM ANDES Lab
//$Author: abeltran2 $
//$LastChangedDate: 2014-06-16 13:16:24 -0700 (Mon, 16 Jun 2014) $

#ifndef PROTOCOL_H
#define PROTOCOL_H

//PROTOCOLS
enum{
	PROTOCOL_PING = 0,
	PROTOCOL_PINGREPLY = 1,
	PROTOCOL_LINKEDLIST = 2,
	PROTOCOL_NAME = 3,
	PROTOCOL_TCP= 4,
	PROTOCOL_DV = 5,
   PROTOCOL_CMD = 99
};

void printProtocol(uint8_t protocol)
{
	switch (protocol)
	{
		case PROTOCOL_PING:
			dbg("protocol", "Protocol Type: PING");
			break;
		case PROTOCOL_PINGREPLY:
			dbg("protocol", "Protocol Type: PING REPLY");
			break;
		case PROTOCOL_LINKEDLIST:
			dbg("protocol", "Protocol Type: LINKED LIST");
			break;
		case PROTOCOL_NAME:
			dbg("protocol", "Protocol Type: NAME");
			break;
		case PROTOCOL_TCP:
			dbg("protocol", "Protocol Type: TCP");
			break;
		case PROTOCOL_CMD:
			dbg("protocol", "Protocol Type: CMD");
			break;
		default:
			dbg("protocol", "Protocol Type: UNKNOWN");
			break;
	}
}

#endif /* PROTOCOL_H */
