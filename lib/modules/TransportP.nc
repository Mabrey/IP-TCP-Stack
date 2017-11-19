#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/channels.h"
#include "../../includes/LSRouting.h"

uses interface Hashmap<socket_store_t> as socketHash;
uses interface List<socket_port_t> as bookedPorts;
uses interface sequencer;
//uses interface 

module TransportP{
   provides interface Transport;
   
   uses interface SimpleSend as Sender;

}

implementation {

    pack sendPackage;
    TCPPack tcpPayload;
    


    //socket_t socket;
    //socket_addr_t sockAddr;

    void initializeSocket(socket_store_t* socket)
    {
        socket_port_t src;
        do
            {
                src = call Random.rand8();
            }while(src == 0 || bookedPorts.contains(src));

        bookedPorts.push(src);

        socket -> state = CLOSED;
        socket -> src = src;
        socket -> dest.port = 0;
        socket -> dest.addr = 0;
        socket -> lastWritten = 0;
        socket -> lastAck = 0;
        socket -> lastSent = 0;
        socket -> lastRead = 0;
        socket -> lastRecd = 0;
        socket -> nextExpected = 0;
    }

    void makeTCPPack(TCPPack *TCPPack, uint8_t srcPort, uint8_t destPort, uint16_t seq, uint8_t flag, uint8_t window, uint8_t *payload, uint8_t length)
    {
        TCPPack -> srcPort = srcPort;
        TCPPack -> destPort = destPort;
        TCPPack -> seq = seq;           //seq num implies the next ack?
        TCPPack -> flag = flag;
        TCPPack -> window = window;
        memcpy(TCPPack->payload, payload, length);
    }

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, TCPPack* payload, uint8_t length){
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }   

    socket_t findPort(uint8_t destPort)
    {
        socket_t fileD = NULL;
        socket_store_t *mySocket;

        for (i = 1; i < MAX_NUM_OF_SOCKETS; i++)
        {
            if(call socketHash.contains(i))
            {
                mySocket = call socketHash.get(i);
                //if the src of client matches the dest of the server
                if (mySocket -> src == destPort)
                {
                    fileD = (uint8_t) i;
                    return fileD;    
                }
            }
        }
        return fileD;
    }

    command void Transport.buildPack(socket_store_t* socket, routingTable Table, uint8_t flag, uint16_t seq)
    {
        
        makeTCPPack(&tcpPayload, socket->src, socket->dest.port, TCPSeq, flag, 0, tcpPayload.payload, sizeof(tcpPayload.payload));
        makePack(&sendPackage, TOS_NODE_ID, socket -> dest.addr, MAX_TTL, PROTOCOL_TCP, call sequencer.getSeq(), (uint8_t*) tcpPayload, sizeof(tcpPayload));
        pushPackList(sendPackage);
        call sequencer.updateSeq();
        call Sender.send(sendPackage, getTableIndex(Table, socket -> dest.addr).hopTo); 
    }



    /**
    * Get a socket if there is one available.
    * @Side Client/Server
    * @return
    *    socket_t - return a socket file descriptor which is a number
    *    associated with a socket. If you are unable to allocated
    *    a socket then return a NULL socket_t.
    */
    command socket_t Transport.socket()
    {
        socket_t fd = NULL;
        socket_store_t newSocket;

        if(!(call socketHash.isFull()))
        {
            do
            {
                fd = (call Random.rand8() % 9) + 1;
            }while(fd == 0 || socketHash.contains(fd));

            //pair fd to socket
            initializeSocket(&newSocket);
            call socketHash.insert(fd, newSocket);
        }
        return fd;
    }

   /**
    * Bind a socket with an address.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       you are binding.
    * @param
    *    socket_addr_t *addr: the source port and source address that
    *       you are bniding to the socket, fd.
    * @Side Client/Server
    * @return error_t - SUCCESS if you were able to bind this socket, FAIL
    *       if you were unable to bind.
    */
   command error_t Transport.bind(socket_t fd, socket_addr_t *addr)
   {
       socket_store_t* bindSocket;

       if (!call socketHash.contains(fd))
       {
           dbg("general", "Can't bind socket to addr");
           return FAIL;
       }
       else
       {
           bindSocket = call Hashmap.get(fd);
           bindSocket -> src = addr.port;
            
           dbg("general", "Socket %d bound to addr", fd);
           return SUCCESS;
       }

   }

   /**
    * Checks to see if there are socket connections to connect to and
    * if there is one, connect to it.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that is attempting an accept. remember, only do on listen. 
    * @side Server
    * @return socket_t - returns a new socket if the connection is
    *    accepted. this socket is a copy of the server socket but with
    *    a destination associated with the destination address and port.
    *    if not return a null socket.
    */
   command socket_t Transport.accept(socket_t fd)
   {
       socket_t fileD = NULL;
       socket_store_t listenSocket;
       socket_store_t* acceptSocket;
       if(call socketHash.contains(fd))
       {
           listenSocket = socketHash.get(fd);
           if (listenSocket-> state == LISTEN)
           {
              fileD = socket(); //create new socket
              if(call socketHash.contains(fileD))
              {
                  acceptSocket = socketHash.get(fileD);
                  acceptSocket -> state = SYN_RCVD;
              }
                  
           }
       }

    else return fileD;

   }

   /**
    * Write to the socket from a buffer. This data will eventually be
    * transmitted through your TCP implimentation.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that is attempting a write.
    * @param
    *    uint8_t *buff: the buffer data that you are going to write from.
    * @param
    *    uint16_t bufflen: The amount of data that you are trying to
    *       submit.
    * @Side For your project, only client side. This could be both though.
    * @return uint16_t - return the amount of data you are able to write
    *    from the pass buffer. This may be shorter then bufflen
    */
   command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen)
   {
       

   }

   /**
    * This will pass the packet so you can handle it internally. 
    * @param
    *    pack *package: the TCP packet that you are handling.
    * @Side Client/Server 
    * @return uint16_t - return SUCCESS if you are able to handle this
    *    packet or FAIL if there are errors.
    */
    command error_t Transport.receive(pack* package)
    {
        pack* myMsg
        socket_store_t* mySocket;
        socket_t fileD;
        TCPPack* tcpPack;
        tcpPack = myMsg->payload;

        switch (tcpPack->flag)
        {

            case 1: //SYN flag
                dbg("general", "SYN Received");
                fileD = call Transport.accept(0);
                if (fileD == NULL)
                    dbg("general", "Could not accept connection");

                else
                {
                    dbg("general", "Accepted Connection");
                    mySocket = socketHash.get(fileD);
                    mySocket -> dest.port = tcpPack -> srcPort;
                    mySocket -> dest.addr = myMsg -> src; 
                    tcpPack->seq = tcpPack->seq + 1;
                    mySocket->state = SYN_RCVD;

                    
                    call Transport.buildPack(&mySocket, confirmedTable, 2, tcpPack->seq);
                    dbg("general", "Sending SYN_ACK");
                }
                    

                break;

            case 2: //SYN_ACK
                int i;
            
                dbg("general", "SYN_ACK Received");
                //we have to find the fd which contains the port

                fileD = call findPort(tcpPack -> destPort);
                if (fileD == NULL)
                {
                    dbg("general", "Could not find port");
                    break;
                } 
               
                //get socket from hashmap using fileD, just to be safe?
                mySocket = call socketHash.get(fileD);

                mySocket -> dest.port = tcpPack -> src;
                tcpPack->seq = tcpPack->seq + 1;
                call Transport.buildPack(&mySocket, confirmedTable, 3, tcpPack->seq);
                mySocket->state = ESTABLISHED;

                dbg("general", "ACK Sent, Socket State: ", mySocket->state);

                break;

            case 3: //ACK
                dbg("general", "ACK Received");
                fileD = call findPort(tcpPack -> destPort);
                if (fileD == NULL)
                {
                    dbg("general", "Could not find port");
                    break;
                } 

                mySocket = call socketHash.get(fileD);

                if (mySocket->state = SYN_RCVD)
                {
                    mySocket->state = ESTABLISHED;
                }
                

                break;

            case 4: //FIN

                break;

            case 5: //DATA


                break;

            default:    //anything else
                dbg("general", "FLAG INVALID");
                break;


        }

   }

   /**
    * Read from the socket and write this data to the buffer. This data
    * is obtained from your TCP implimentation.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that is attempting a read.
    * @param
    *    uint8_t *buff: the buffer that is being written.
    * @param
    *    uint16_t bufflen: the amount of data that can be written to the
    *       buffer.
    * @Side For your project, only server side. This could be both though.
    * @return uint16_t - return the amount of data you are able to read
    *    from the pass buffer. This may be shorter then bufflen
    */
   command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen)
   {


   }

   /**
    * Attempts a connection to an address.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that you are attempting a connection with. 
    * @param
    *    socket_addr_t *addr: the destination address and port where
    *       you will atempt a connection.
    * @side Client
    * @return socket_t - returns SUCCESS if you are able to attempt
    *    a connection with the fd passed, else return FAIL.
    */
   command error_t Transport.connect(socket_t fd, socket_addr_t * addr, routingTable Table)
   {
        socket_store_t* synSocket;
        int seq = call Random.rand16(); //this is how tcp picks sequence numbers, at random instead of sequentially

        if (call socketHash.contains(fd))
        {
            synSocket = call Hashmap.get(fd);
            synSocket -> dest.port = addr -> port;
            synSocket -> dest.addr = addr -> addr;
            //make a tcp packet, then add the header of the "IP" layer
            makeTCPPack(&tcpPayload, synSocket->src, addr.port, seq, 1, 0, tcpPayload.payload, sizeof(tcpPayload.payload));
            makePack(&sendPackage, TOS_NODE_ID, synSocket -> dest.addr, MAX_TTL, PROTOCOL_TCP, call sequencer.getSeq(), (uint8_t*) tcpPayload, sizeof(tcpPayload));
            call Sender.send(sendPackage, getTableIndex(Table, synSocket -> dest.addr).hopTo);
            call sequencer.updateSeq();
            synSocket->state = SYN_SENT;
            return SUCCESS;
        }
        else return FAIL;
   }

   /**
    * Closes the socket.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that you are closing. 
    * @side Client/Server
    * @return socket_t - returns SUCCESS if you are able to attempt
    *    a closure with the fd passed, else return FAIL.
    */
   command error_t Transport.close(socket_t fd)
   {
      

   }

   /**
    * A hard close, which is not graceful. This portion is optional.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that you are hard closing. 
    * @side Client/Server
    * @return socket_t - returns SUCCESS if you are able to attempt
    *    a closure with the fd passed, else return FAIL.
    */
   command error_t Transport.release(socket_t fd)
   {


   }

   /**
    * Listen to the socket and wait for a connection.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that you are hard closing. 
    * @side Server
    * @return error_t - returns SUCCESS if you are able change the state 
    *   to listen else FAIL.
    */
   command error_t Transport.listen(socket_t fd)
   {
       socket_t fileD;
       socket_store_t* socket;
       if(socketHash.contains(fd))
       {
           socket = socketHash.get(fd);
           if(socket -> state == CLOSED)
           {
               socket -> state = LISTEN;
               return SUCCESS;
           }
       }
       else return FAIL;

   }




}