#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/channels.h"
#include "../../includes/LSRouting.h"


//uses interface 

module TransportP{
    provides interface Transport;
    uses interface Hashmap<socket_store_t> as socketHash;
    uses interface List<socket_port_t> as bookedPorts;
    uses interface List<pack> as packList;
    uses interface sequencer;
    uses interface SimpleSend as Sender;
    uses interface Random as Random;

}

implementation {

    pack sendPackage;
    routingTable confirmedTable;
    TCPpack tcpPayload;
    int TCPSeq = 0;


    //socket_t socket;
    //socket_addr_t sockAddr;

    bool checkPort(socket_port_t port)
    {
        int i;
        for (i = 0; i < call bookedPorts.size(); i++)
        {
            if (port == call bookedPorts.get(i))
                return TRUE;
        }

        return FALSE;
    }    

    void makeTCPPack(TCPpack *TCPPack, uint8_t srcPort, uint8_t destPort, uint16_t seq, uint8_t flag, uint8_t window, uint8_t *payload, uint8_t length)
    {
        TCPPack -> srcPort = srcPort;
        TCPPack -> destPort = destPort;
        TCPPack -> seq = seq;           //seq num implies the next ack?
        TCPPack -> flag = flag;
        TCPPack -> window = window;
        memcpy(TCPPack->payload, payload, length);
    }

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, TCPpack* payload, uint8_t length){
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }   

    socket_t findPort(uint8_t destPort)
    {
        socket_t i;
        socket_t fileD = 0;
        socket_store_t mySocket;

        for (i = 2; i < 12; i++)
        {
            if(call socketHash.contains(i))
            {
                mySocket = call socketHash.get(i);
                //if the src of client matches the dest of the server
                if (mySocket.src == destPort)
                {
                    fileD = (uint8_t) i;
                    return fileD;    
                }
            }
        }
        return fileD;
    }

    command void Transport.updateTable(routingTable table)
    {
        confirmedTable = table;
    }
   
    command void Transport.initializeSocket(socket_store_t* socket)
    {
        socket_port_t src;
        do
            {
                src = call Random.rand16()%255;
            }while(src == 0 || checkPort(src));

        call bookedPorts.pushback(src);

        socket -> state = CLOSED;
        socket -> src = src;
        socket -> dest.port = 0;
        socket -> dest.addr = 0;
        socket -> lastWritten = 0;
        socket -> lastAck = 0;
        socket -> lastSent = 0;
        socket -> lastRead = 0;
        socket -> lastRcvd = 0;
        socket -> nextExpected = 0;
    }

    command void Transport.buildPack(socket_store_t* socket, routingTable Table, uint8_t flag)
    {
        
        makeTCPPack(&tcpPayload, socket->src, socket->dest.port, TCPSeq, flag, 0, tcpPayload.payload, sizeof(tcpPayload.payload));
        makePack(&sendPackage, TOS_NODE_ID, socket -> dest.addr, MAX_TTL, PROTOCOL_TCP, call sequencer.getSeq(), &tcpPayload, sizeof(tcpPayload));
        //pushPackList(sendPackage);
        TCPSeq++;       //update sequence different, to maintain difference between sockets
        call sequencer.updateSeq();
        call Sender.send(sendPackage, getTableIndex(&Table, socket -> dest.addr).hopTo); 
    }

    command void Transport.createServerSocket()
    {
        socket_t fd = 1; 
        socket_store_t newSocket;
        call Transport.initializeSocket(&newSocket);
        newSocket.state = LISTEN;
        call socketHash.insert(fd, newSocket);
        //dbg("general", "Server Socket Initialized\n");
        //dbg("general", "Hashmap size: %d \n", call socketHash.size());
        //dbg("general", "COPY\n");


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
        socket_t fd = 0;
        socket_store_t newSocket;

        if(call socketHash.size() < 10)
        {
            do
            {
                fd = (call Random.rand16() % 11);
            }while(fd == 0 || fd == 1 ||call socketHash.contains(fd));

            //pair fd to socket
            call Transport.initializeSocket(&newSocket);
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
       socket_store_t bindSocket;

       if (!call socketHash.contains(fd))
       {
           dbg("general", "Can't bind socket to addr\n");
           return FAIL;
       }
       else
       {
           bindSocket = call socketHash.get(fd);
           call socketHash.remove(fd);
           bindSocket.src = addr -> port;
           call socketHash.insert(fd, bindSocket);
            
           dbg("general", "Socket %d bound to addr\n", fd);
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
       socket_t fileD = 0;
       socket_store_t listenSocket;
       socket_store_t acceptSocket;
       if(call socketHash.contains(fd))
       {
           listenSocket = call socketHash.get(fd);
           if (listenSocket.state == LISTEN)
           {
              fileD = call Transport.socket(); //create new socket
              if(call socketHash.contains(fileD))
              {
                  //acceptSocket = call socketHash.get(fileD);
                  //call socketHash.remove(fileD);
                  //acceptSocket.state = SYN_RCVD;
                 // call socketHash.insert(fileD, acceptSocket);
              }
                  
           }
       }

        return fileD;

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
        socket_store_t mySocket;
        socket_t fileD;
        TCPpack* tcpPack;
        tcpPack = (TCPpack*) package->payload;
        //int i;

        switch (tcpPack->flag)
        {

            case 1: //SYN flag
                dbg("general", "SYN Received\n");
                fileD = call Transport.accept(1);
                if (fileD == 0 && fileD == 1)
                    dbg("general", "Could not accept connection\n");

                else
                {
                    dbg("general", "Accepted Connection\n");
                    mySocket = call socketHash.get(fileD);
                    call socketHash.remove(fileD);
                    mySocket.dest.port = tcpPack -> srcPort;
                    mySocket.dest.addr = package -> src; 
                    tcpPack->seq = tcpPack->seq + 1;
                    mySocket.state = SYN_RCVD;
                    call socketHash.insert(fileD, mySocket);

                    
                    call Transport.buildPack(&mySocket, confirmedTable, 2);
                    dbg("general", "Sending SYN_ACK\n");
                }
                    

                break;

            case 2: //SYN_ACK
                
            
                dbg("general", "SYN_ACK Received\n");
                //we have to find the fd which contains the port

                fileD = findPort(tcpPack -> destPort);
                if (fileD == 0)
                {
                    dbg("general", "Could not find port\n");
                    break;
                } 
               
                //get socket from hashmap using fileD, just to be safe?
                mySocket = call socketHash.get(fileD);
                call socketHash.remove(fileD);

                mySocket.dest.port = package -> src;
                mySocket.state = ESTABLISHED;
                call socketHash.insert(fileD, mySocket);
                tcpPack->seq = tcpPack->seq + 1;
                call Transport.buildPack(&mySocket, confirmedTable, 3);
                

                dbg("general", "ACK Sent, Socket State: %d \n", mySocket.state);

                break;

            case 3: //ACK
                dbg("general", "ACK Received\n");
                fileD = findPort(tcpPack -> destPort);
                if (fileD == 0 || fileD == 1)
                {
                    dbg("general", "Could not find port\n");
                    break;
                } 

                mySocket = call socketHash.get(fileD);

                if (mySocket.state == SYN_RCVD)
                {
                    mySocket.state = ESTABLISHED;
                }
                

                break;

            case 4: //FIN

                break;

            case 5: //DATA


                break;

            default:    //anything else
                dbg("general", "FLAG INVALID\n");
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
   command error_t Transport.connect(socket_t fd, socket_addr_t * addr)
   {
        socket_store_t synSocket;
        int seq = call Random.rand16(); //this is how tcp picks sequence numbers, at random instead of sequentially

        if (call socketHash.contains(fd))
        {
            synSocket = call socketHash.get(fd);
            synSocket.dest.port = addr -> port;
            synSocket.dest.addr = addr -> addr;
            //make a tcp packet, then add the header of the "IP" layer
            dbg("general", "Getting TCP Package Ready\n");
            makeTCPPack(&tcpPayload, synSocket.src, addr->port, seq, 1, 0, tcpPayload.payload, sizeof(tcpPayload.payload));
            makePack(&sendPackage, TOS_NODE_ID, synSocket.dest.addr, MAX_TTL, PROTOCOL_TCP, call sequencer.getSeq(), &tcpPayload, sizeof(tcpPayload));
            call Sender.send(sendPackage, getTableIndex(&confirmedTable, synSocket.dest.addr).hopTo);
            dbg("general", "TCP Package Sent. Seq: %d\n",call sequencer.getSeq());
            call sequencer.updateSeq();
            synSocket.state = SYN_SENT;
            call socketHash.remove(fd);
            call socketHash.insert(fd, synSocket);
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
       //socket_t fileD;
       
       socket_store_t socket;
      // dbg("general", "Listen Called\n");
       if(call socketHash.contains(fd))
       {
           //dbg("general", "SocketHash contains fd: %d\n", fd);
           socket = call socketHash.get(fd);
           //dbg("general", "Socket obtained\n");
           if(socket.state == LISTEN)
           {
               return SUCCESS;
           }
       }
       else return FAIL;

   }




}