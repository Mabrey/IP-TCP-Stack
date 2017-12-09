#ifndef __SOCKET_H__
#define __SOCKET_H__

enum{
    MAX_NUM_OF_SOCKETS = 10,
    ROOT_SOCKET_ADDR = 255,
    ROOT_SOCKET_PORT = 255,
    SOCKET_BUFFER_SIZE = 128,
};

enum commandType{
    HELLO = 0,
    MSG = 1,
    WHISPER = 2,
    LIST = 3,
};

enum socket_state{
    CLOSED = 0,
    LISTEN = 1,
    ESTABLISHED = 2,
    SYN_SENT = 3,
    SYN_RCVD = 4,
    CLOSE_WAIT = 5,
    FIN_WAIT_1 = 6,
    FIN_WAIT_2 = 7,
    TIME_WAIT = 8,
    LAST_ACK = 9,
};


typedef nx_uint8_t nx_socket_port_t;
typedef uint8_t socket_port_t;

// socket_addr_t is a simplified version of an IP connection.
typedef nx_struct socket_addr_t{
    nx_socket_port_t port;
    nx_uint16_t addr;
}socket_addr_t;


// File descripter id. Each id is associated with a socket_store_t
typedef uint8_t socket_t;

// State of a socket. 
typedef struct socket_store_t{
    
    uint8_t flag;
    char name[16];
    char message[64];
    char cmdBuff[8];
    enum socket_state state;
    enum commandType commandT;
    bool endMsg;
    bool cmd; 
    socket_port_t src;
    socket_addr_t dest;
    uint16_t seqStart;

    // This is the sender portion.
    uint8_t sendBuff[SOCKET_BUFFER_SIZE];
    uint8_t lastWritten;
    uint8_t lastAck;
    uint8_t lastSent;

    // This is the receiver portion
    uint8_t rcvdBuff[SOCKET_BUFFER_SIZE];
    uint8_t lastRead;
    uint8_t lastRcvd;
    uint8_t nextExpected;
    uint8_t msgLastEnd;
    uint8_t msgLastWritten;
    uint8_t cmdLastWritten;

    uint16_t RTT;
    uint16_t maxTransfer;
    uint8_t effectiveWindow;
}socket_store_t;

#endif