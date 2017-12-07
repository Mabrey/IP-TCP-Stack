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
    uses interface Timer<TMilli> as TimeoutTimer;
    uses interface Timer<TMilli> as WriteTimer;
    uses interface Timer<TMilli> as ReadTimer;
    uses interface Timer<TMilli> as CloseTimer;

}

implementation {

    pack sendPackage;
    bool clientFD[10];
    bool serverFD[10];
    routingTable confirmedTable;
    TCPpack tcpPayload;
    int TCPSeq = 0;
    bool rttFound = FALSE;
    uint8_t rttStart;
    uint8_t rttFinish;
    uint8_t rtt;


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

    void makeTCPPack(TCPpack *TCPPack, uint8_t srcPort, uint8_t destPort, uint16_t seq, uint8_t flag, uint8_t window, uint16_t *payload, uint8_t length)
    {
        TCPPack -> srcPort = srcPort;
        TCPPack -> destPort = destPort;
        TCPPack -> seq = seq;           //seq num implies the next ack?
        TCPPack -> flag = flag;
        TCPPack -> window = window;
        memcpy(TCPPack->payload, payload, length);
        //dbg("general", "Flag = %d        TCPFlag = %d\n", flag, TCPPack->flag);
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

    event void TimeoutTimer.fired(){
        dbg("general", "Timeout Fired\n");
    }

    event void WriteTimer.fired()
    {
        //decide on buffer size to pass to sendBuff
        uint16_t buff16[16];
        uint8_t buff8[32];
        int i, j, k;
        int count = 0;
        uint16_t lastNumTop;
        uint16_t lastNumBot;
        uint16_t lastNum;
        socket_store_t mySocket;

        //dbg("general", "--------------Write Timer Started-------------\n");

        //need to write to all sockets currently open
        for(i = 2; i <= 10; i++)
        {
            if (call socketHash.contains(i))
            {
                mySocket = call socketHash.get(i);
                if (clientFD[i] == TRUE)
                {
                    //retrieve the last number written to buffSend
                    lastNumTop = mySocket.sendBuff[mySocket.lastWritten];
                    lastNumTop <<= 8;
                    lastNumBot = mySocket.sendBuff[mySocket.lastWritten-1];
                    lastNum = lastNumTop | lastNumBot;
                    //dbg("general", "LastNum = %d\n", lastNum);

                    //fill buff with whatever was left off with 
                    for (j = 0; j < 16; j++)
                    {
                        if((lastNum + 1 + j) <= mySocket.maxTransfer)
                        {
                            buff16[j] = lastNum + 1 + j;
                            count += 2;
                        }
                        
                        else break;
                    }
                    
                    memcpy(&buff8, buff16, sizeof(buff16));
                     /*
                    printf("Fd: %d    count: %d\n", i, count);    
                    for (k = 0; k < count; k++)
                    {
                        printf("buff: %d\n", buff8[k]);
                    }
                    */
                    dbg("general", "Count = %d\n", count);
                    call Transport.write(i, buff8, count);
                    mySocket = call socketHash.get(i);
                    //call Transport.dataSend(i);
                    
                }
            }
        }
        //dbg("general", "Timer Finished\n");
        call WriteTimer.startPeriodic(5000);
    }

    event void ReadTimer.fired()
    {
        int i, count;
        TCPpack payload;
        socket_store_t mySocket;
        //dbg("general","Read Timer Called\n");

        for (i = 2; i <= 10; i++)
        {
             if (call socketHash.contains(i))
            {
                mySocket = call socketHash.get(i);
                if (serverFD[i] == TRUE)
                {
                    count = call Transport.read(i);
                    //printf("Count: %d\n", count); 
                    mySocket = call socketHash.get(i);
                    call socketHash.remove(i);
                    mySocket.nextExpected = (mySocket.nextExpected + (2 * count)) % 128;
                    mySocket.effectiveWindow = ( mySocket.effectiveWindow + (2* count)) % 128;
                    call socketHash.insert(i, mySocket);
                    if (count > 0)
                    {
                        //create an ack packet to signal next batch 
                        dbg("general", "Sending Ack\n");
                        makeTCPPack(&payload, mySocket.src, mySocket.dest.port, mySocket.nextExpected, 3, mySocket.effectiveWindow, payload.payload, sizeof(payload.payload));
                        makePack(&sendPackage, TOS_NODE_ID, mySocket.dest.addr, MAX_TTL, PROTOCOL_TCP, call sequencer.getSeq(), &payload, sizeof(payload));
                        call sequencer.updateSeq();
                        call Sender.send(sendPackage, getTableIndex(&confirmedTable, mySocket.dest.addr).hopTo);

                        if (mySocket.state == 9)
                        {
                            dbg("general", "Sending FIN\n");
                            makeTCPPack(&payload, mySocket.src, mySocket.dest.port, mySocket.nextExpected, 4, mySocket.effectiveWindow, 0, 0);
                            makePack(&sendPackage, TOS_NODE_ID, mySocket.dest.addr, MAX_TTL, PROTOCOL_TCP, call sequencer.getSeq(), &payload, sizeof(payload));
                            call sequencer.updateSeq();
                            call Sender.send(sendPackage, getTableIndex(&confirmedTable, mySocket.dest.addr).hopTo);
                            call Transport.close(i);

                        }
                    }
                
                }
            }
        }

    }

    event void CloseTimer.fired()
    {
        int i = 0;
        socket_store_t mySocket;
        for(i = 2; i <= 10; i++)
        {
            if (call socketHash.contains(i))
            {
                mySocket = call socketHash.get(i);
                if(mySocket.state == 8)
                    call Transport.close(i);
            }
        }
    }
        

    command error_t Transport.dataSend(socket_t fd)
    {
        socket_store_t mySocket = call socketHash.get(fd);
       
        uint8_t payloadSize;
        uint16_t outbuff[6];
        uint16_t top = 0;
        uint16_t bot = 0;
        uint16_t completeNum = 0;
        bool msgFin = FALSE;
        int i, j, start;
        int window;
        dbg("general", "FileD: %d\n", fd);

        //call socketHash.remove(fd);
        //dbg("general", "Last Written: %d        Last Sent: %d\n", mySocket.lastWritten, mySocket.lastSent);
        //find count between lastSent and lastWritten

        if (mySocket.lastWritten >= mySocket.lastSent)
            window = mySocket.lastWritten - mySocket.lastSent;
        
        else if (mySocket.lastWritten < mySocket.lastSent)
            window = 128 - (mySocket.lastSent - mySocket.lastWritten);
        
        if (window > 12)
            window = 12;

        if (window == 0)
            return FAIL;

        if (window % 2 == 1)
            window--;
        //pull from sendBuff to create the payload since payload is in
        //16 bit increments, but buff is in 8, we take 2 buff slots per
        //number and use bitshift to concatenate the top and bot. Update lastSent. 
        j = 0;
        
        start = (mySocket.lastSent + 1) % 128;
        for (i = start; i < start + window; i += 2)
        {
            bot = mySocket.sendBuff[(i)%128];
            
            top = mySocket.sendBuff[(i + 1)%128];
            top <<= 8;
            completeNum = top | bot;
            outbuff[j] = completeNum;
            printf("SendBuff = %d,   bot: %d,    top:%d\n", completeNum, bot, top);
            if (completeNum == mySocket.maxTransfer)
                msgFin = TRUE;
            j++;
        }
        mySocket.lastSent = (mySocket.lastSent + window) % 128;
        /*
            for(i = 0; i < window/2; i++)
                printf("Buff[%d] = %d\n", i, outbuff[i]);

            for(i = mySocket.lastSent; i < mySocket.lastSent + window; i++)
                printf("Buff = %d\n", mySocket.sendBuff[i]);
        */
        call socketHash.remove(fd);
        call socketHash.insert(fd, mySocket);
        dbg("general", "Window = %d\n", window);
        //create a TCP packet
        makeTCPPack(&tcpPayload, mySocket.src, mySocket.dest.port, mySocket.nextExpected, 5, window, outbuff, sizeof(outbuff));
        makePack(&sendPackage, TOS_NODE_ID, mySocket.dest.addr, MAX_TTL, PROTOCOL_TCP, call sequencer.getSeq(), &tcpPayload, sizeof(tcpPayload));
        call sequencer.updateSeq();
        call Sender.send(sendPackage, getTableIndex(&confirmedTable, mySocket.dest.addr).hopTo);

        if (msgFin)
        {
            makeTCPPack(&tcpPayload, mySocket.src, mySocket.dest.port, mySocket.nextExpected, 4, window, 0, 0);
            makePack(&sendPackage, TOS_NODE_ID, mySocket.dest.addr, MAX_TTL, PROTOCOL_TCP, call sequencer.getSeq(), &tcpPayload, sizeof(tcpPayload));
            call sequencer.updateSeq();
            call Sender.send(sendPackage, getTableIndex(&confirmedTable, mySocket.dest.addr).hopTo);
            call Transport.close(fd);
        }
        return SUCCESS;
        
    }

    command uint16_t Transport.storeData(socket_t fd, uint16_t *buff16, int bufflen)
    {
        socket_store_t mySocket;
        int i, j;
        int buffFree;
        int startWrite;
        uint8_t buff8[12];
        if (call socketHash.contains(fd))
            mySocket = call socketHash.get(fd);

        else
        {
            dbg("general", "Socket not contained, could not store data\n");
            return 0;
        }
         printf("bufflen = %d\n", bufflen);
        //checking how much buff space is free

        //check if last written = lastRead AKA the whole buffer is empty
        if (mySocket.lastRcvd == mySocket.lastRead )
            buffFree = SOCKET_BUFFER_SIZE - 1;
        
        //last written is greater than last ack
        else if (mySocket.lastRcvd > mySocket.lastRead)
            buffFree = SOCKET_BUFFER_SIZE - (mySocket.lastRcvd - mySocket.lastRead) -  1;
        
        //last ack is greater than last written, last written has wrapped around
        else if (mySocket.lastRcvd < mySocket.lastRead)
            buffFree = mySocket.lastRead - mySocket.lastRcvd - 1;
        
        //check if bufflen >= buffFree
        if (bufflen > buffFree)
            bufflen = buffFree;

        printf("buffFree = %d\n", buffFree);
        //the buffer is full, and cannot accept anything
        if (bufflen == 0)
            return 0;

        //find starting place to write in buffer. different for adding to buffer rather than beginning from blank buffer
        startWrite = mySocket.lastRcvd + 1;
        printf("Last Rcvd: %d,   StartWrite: %d\n", mySocket.lastRcvd, startWrite);
        if (mySocket.lastRcvd == mySocket.lastRead && mySocket.lastRcvd == mySocket.lastSent 
            && mySocket.lastRcvd == 0 && mySocket.sendBuff[0] == 0)
            startWrite = 0;

        memcpy(&buff8, buff16, bufflen);

        //printf("start: %d\n", startWrite);
        //write to the send buffer and update its last written;
        printf("bufflen = %d\n", bufflen);
        for (i = 0; i < bufflen; i++)
        {
            //temp[i] = buff[i];
            j = (startWrite + i) % 128;
            mySocket.rcvdBuff[j] = buff8[i];
            printf("rcvdBuff[%d] = %d\n", j, buff8[i]);
            
        }
        mySocket.lastRcvd = j;
        
        /*  printf("last received: %d    buff[0]: %d    buff[1]:%d\n", mySocket.lastRcvd, mySocket.rcvdBuff[0], mySocket.rcvdBuff[1]);
            printf("                    buff[2]: %d    buff[3]:%d\n", mySocket.rcvdBuff[2], mySocket.rcvdBuff[3]);
            printf("                    buff16[0]: %d\n", buff16[0]);
        */  //add socket back to hashmap and return how many things were added to sendBuff
        call socketHash.remove(fd);
        call socketHash.insert(fd, mySocket);

        return bufflen;
    }

    command void Transport.updateRTT()
    {
        rttFinish = call TimeoutTimer.getNow();
        rtt = rttFinish - rttStart;
    }

    command void Transport.updateTable(routingTable table)
    {
        confirmedTable = table;
    }

    command void Transport.updateMaxTransfer(uint16_t max, socket_store_t* socket)
    {
        socket -> maxTransfer = max;
    }
   
    command void Transport.initializeSocket(socket_store_t* socket)
    {
        int i;
        socket_port_t src;
        do
            {
                src = call Random.rand16()%255;
            }while(src == 0 || checkPort(src));

        call bookedPorts.pushback(src);
        dbg("general", "SRC: %d\n", src);

        socket -> state = CLOSED;
        socket -> src = src;
        socket -> dest.port = 0;
        socket -> dest.addr = 0;
        socket -> lastWritten = 127;
        socket -> lastAck = 127;
        socket -> lastSent = 127;
        socket -> lastRead = 127;
        socket -> lastRcvd = 127;
        socket -> nextExpected = 0;
        socket -> effectiveWindow = 128;

        for (i = 0; i < 128; i++)
        {
            socket -> rcvdBuff[i] = 0;
            socket -> sendBuff[i] = 0;
        }
    }

    command void Transport.buildPack(socket_store_t* socket, routingTable Table, uint8_t flag, uint8_t window)
    {
        
        makeTCPPack(&tcpPayload, socket->src, socket->dest.port, socket->nextExpected, flag, window, tcpPayload.payload, sizeof(tcpPayload.payload));
        makePack(&sendPackage, TOS_NODE_ID, socket -> dest.addr, MAX_TTL, PROTOCOL_TCP, call sequencer.getSeq(), &tcpPayload, sizeof(tcpPayload));
        //pushPackList(sendPackage);

        call sequencer.updateSeq();
        call Sender.send(sendPackage, getTableIndex(&Table, socket -> dest.addr).hopTo); 
    }

    command void Transport.createServerSocket()
    {
        socket_t fd = 1; 
        socket_store_t newSocket;
        serverFD[fd] = TRUE;
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
            //dbg("general", "SRC: %d\n", newSocket.src);
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

             // if(call socketHash.contains(fileD))
              //{
                  //acceptSocket = call socketHash.get(fileD);
                  //call socketHash.remove(fileD);
                  //acceptSocket.state = SYN_RCVD;
                 // call socketHash.insert(fileD, acceptSocket);
              //}
                  
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
        int i, j, startWrite;
        int buffFree;
        //uint8_t temp[8];
        socket_store_t mySocket;

        if (call socketHash.contains(fd))
            mySocket = call socketHash.get(fd);

        else
        {
            dbg("general", "Socket not contained, could not write\n");
            return 0;
        }

        dbg("general", "last Written: %d    last ack: %d\n", mySocket.lastWritten, mySocket.lastAck);
        //checking how much buff space is free

        //check if last written = lastAck AKA the whole buffer is empty
        if (mySocket.lastWritten == mySocket.lastAck )
            buffFree = SOCKET_BUFFER_SIZE - 2;
        
        //last written is greater than last ack
        else if (mySocket.lastWritten > mySocket.lastAck)
            buffFree = SOCKET_BUFFER_SIZE - (mySocket.lastWritten - mySocket.lastAck) -  2;
        
        //last ack is greater than last written, last written has wrapped around
        else if (mySocket.lastWritten < mySocket.lastAck)
            buffFree = mySocket.lastAck - mySocket.lastWritten - 2;
        
        //check if bufflen >= buffFree
        if (bufflen > buffFree)
            bufflen = buffFree;

        //the buffer is full, and cannot accept anything
        if (bufflen == 0)
            return 0;
        printf("BuffFree: %d    LastAck: %d\n", buffFree, mySocket.lastAck);
        //find starting place to write in buffer. different for adding to buffer rather than beginning from blank buffer
        startWrite = mySocket.lastWritten + 1;
        printf("Last Written: %d,   StartWrite: %d\n", mySocket.lastWritten, startWrite);
    /*    if (mySocket.lastWritten == mySocket.lastAck && mySocket.lastWritten == mySocket.lastSent 
            && mySocket.lastWritten == 0 && mySocket.sendBuff[0] == 0)
            startWrite = 0;
    */    //printf("start: %d\n", startWrite);
        //write to the send buffer and update its last written;
        for (i = 0; i < bufflen; i++)
        {
            //temp[i] = buff[i];
            j = (startWrite + i) % 128;
            mySocket.sendBuff[j] = buff[i];
            printf("Write To sendBuff[%d]: %d\n", j, buff[i]);
        }
        mySocket.lastWritten = j;
        
    //    printf("last written: %d    buff[0]: %d    buff[1]:%d\n", mySocket.lastWritten, mySocket.sendBuff[0], mySocket.sendBuff[1]);
    //    printf("                    buff[2]: %d    buff[3]:%d\n", mySocket.sendBuff[2], mySocket.sendBuff[3]);
        //add socket back to hashmap and return how many things were added to sendBuff
        call socketHash.remove(fd);
        call socketHash.insert(fd, mySocket);

        return bufflen;

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
   command uint16_t Transport.read(socket_t fd)
   {
        int i, j, k, buffUsed;
        int count = 0;
        int printCount = 1;
        socket_store_t mySocket;
        uint16_t tempNextVal;
        uint16_t tempNextSwap;
        uint16_t top;
        uint16_t bot;
        uint16_t completeNum;
        bool found = FALSE; 

        if (call socketHash.contains(fd))
        {
            mySocket = call socketHash.get(fd);
            //call socketHash.remove(fd);
        }

        else
        {
            dbg("general", "Socket not contained, could not read\n");
            return 0;
        }
       /* 
        for(i = 0; i <= 127; i++)
        {
            printf("rcvdBuff[%d] = %d\n", i, mySocket.rcvdBuff[i]);
        }
        */
        //Find amount of space is used in rcvdBuff
        if (mySocket.lastRcvd >= mySocket.lastRead)
            buffUsed = (mySocket.lastRcvd - mySocket.lastRead) + 1;
        
        else if (mySocket.lastRcvd < mySocket.lastRead)
            buffUsed = 129 - (mySocket.lastRead - mySocket.lastRcvd);

        //printf("Last Read: %d\n", mySocket.lastRead);

        //Check from lastRead for the next in sequence. Swap the next value with
        //the buffer space in front of lastRead if not already there and update last read.
        for (i = 1; i < buffUsed; i += 2)
        {
            bot = mySocket.rcvdBuff[(mySocket.lastRead - 1)%128];
            top = mySocket.rcvdBuff[(mySocket.lastRead)%128];
            top <<= 8;
            completeNum = top | bot;
            //printf("CompleteNum = %d    Bot = %d    Top = %d\n", completeNum, bot, top);


            tempNextVal = completeNum + 1;
            //for(j = 1; j < buffUsed; j++)
            //check within the buff for matching the next expected result
            //if found, count++ and lastRead++, then print the number
            for(j = (mySocket.lastRead + 1)%128; j != mySocket.lastRcvd ; j += 2)
            {
                bot = mySocket.rcvdBuff[j];
                top = mySocket.rcvdBuff[j+1];
                top <<= 8;
                completeNum = top | bot;
                dbg("general", "Num: %d,    Temp:%d\n", completeNum, tempNextVal);
                if (completeNum == tempNextVal )
                {
                    k = j;

                    if (k == (mySocket.lastRead + 1))
                    {
                        found = TRUE;
                    }

                    else if (k != (mySocket.lastRead + 1) )
                    {
                        //bottom half swap
                        tempNextSwap = mySocket.rcvdBuff[(mySocket.lastRead + 1)%128];
                        mySocket.rcvdBuff[(mySocket.lastRead + 1)%128] = bot;
                        mySocket.rcvdBuff[k] = tempNextSwap;
                        //top half swap
                        tempNextSwap = mySocket.rcvdBuff[(mySocket.lastRead + 2)%128];
                        mySocket.rcvdBuff[(mySocket.lastRead + 2)%128] = (top >> 8);
                        mySocket.rcvdBuff[k+1] = tempNextSwap;
                        found = TRUE;
                    }
                }
                if (found)
                {
                    printf("%d, ", tempNextVal);
                    if ( (printCount % 7 ) == 0|| ((j + 1) == mySocket.lastRcvd))
                        printf("\n");
                    mySocket.lastRead =  (mySocket.lastRead+2)%128; 
                    count++;
                    printCount++;
                    break;
                }
               
            }
            if (!found)
            {
                dbg("general", "Next was not found in buff\n");
                break;
            }
            
        }
        call socketHash.remove(fd);
        call socketHash.insert(fd, mySocket);

       
        return count;

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
        int i;
        socket_store_t mySocket;
        socket_t fileD;
        uint16_t buffer[6];
        TCPpack* tcpPack;
        tcpPack = (TCPpack*) package->payload;
        //int i;
        dbg("general", "Flag = %d\n", tcpPack->flag);
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
                    //keep track of fd associated with server
                    serverFD[fileD] = TRUE;
                    mySocket = call socketHash.get(fileD);
                    call socketHash.remove(fileD);
                    mySocket.dest.port = tcpPack -> srcPort;
                    mySocket.dest.addr = package -> src; 
                    mySocket.seqStart = tcpPack -> seq;
                    mySocket.nextExpected =  tcpPack -> seq - mySocket.seqStart;
                    dbg("general", "SrcPort: %d\n", tcpPack -> srcPort);
                    tcpPack->seq = tcpPack->seq + 1;
                    mySocket.state = SYN_RCVD;
                    call socketHash.insert(fileD, mySocket);

                    
                    call Transport.buildPack(&mySocket, confirmedTable, 2, SOCKET_BUFFER_SIZE);
                    //rttStart = call TimeoutTimer.getNow();
                    //dbg("general", "Starting rtt\n");
                    dbg("general", "Sending SYN_ACK\n");
                }
                    

                break;

            case 2: //SYN_ACK
                
            
                dbg("general", "SYN_ACK Received\n");
                /*
                if (rttFound == FALSE)
                {
                    call Transport.updateRTT();
                    rttFound = TRUE;
                }
                //dbg("general", "RTT: %d\n", rtt);
                */

                //we have to find the fd which contains the port
                fileD = findPort(tcpPack -> destPort);
                dbg("general", "FileD: %d   Port: %d\n", fileD, tcpPack->destPort);

                if (fileD == 0)
                {
                    dbg("general", "Could not find port\n");
                    break;
                } 
               
                //get socket from hashmap using fileD, just to be safe?
                mySocket = call socketHash.get(fileD);

                //keep track of fd that are associated with clients
                

                //client is established but ack did not make it to server yet/at all
                if (mySocket.state == ESTABLISHED)
                {
                    call Transport.buildPack(&mySocket, confirmedTable, 3, SOCKET_BUFFER_SIZE);
                    dbg("general", "Client Resending ACK\n");
                    break;
                }

                //Client is not established yet
                if (mySocket.state == SYN_SENT)
                {

                    call socketHash.remove(fileD);
                    mySocket.dest.port = tcpPack -> srcPort;
                    mySocket.nextExpected = tcpPack -> seq;
                    mySocket.state = ESTABLISHED;
                    mySocket.effectiveWindow = SOCKET_BUFFER_SIZE;
                    dbg("general", "SRC: %d\n", tcpPack -> srcPort);
                    call socketHash.insert(fileD, mySocket);
                    call Transport.buildPack(&mySocket, confirmedTable, 3, SOCKET_BUFFER_SIZE);
        
                    dbg("general", "ACK Sent, Socket State: %d \n", mySocket.state);

                    for (i = 0; i < 3; i++)
                    {
                        if (mySocket.state == 2)
                            call Transport.dataSend(fileD);
                    }
                       
                   
                    //After ACK, assume it got the message and start sending data. 
                }

                

                break;

            case 3: //ACK
                dbg("general", "ACK Received\n");
                if (rttFound == FALSE)
                {
                    //call Transport.updateRTT();
                    rttFound = TRUE;
                }

                //find fd using this port
                fileD = findPort(tcpPack -> destPort);
                dbg("general", "FileD: %d   Port: %d\n", fileD, tcpPack->destPort);
                
                if (fileD == 0 || fileD == 1)
                {
                    dbg("general", "Could not find port\n");
                    break;
                } 

                mySocket = call socketHash.get(fileD);
                

                //the server is receiving an ack
                if (mySocket.state == SYN_RCVD)
                {
                    call socketHash.remove(fileD);
                    mySocket.state = ESTABLISHED;
                    
                    call socketHash.insert(fileD, mySocket);
                   
                    dbg("general", "Read Timer started\n");
                    dbg("general", "Socket Established\n");    
                    dbg("general", "Waiting for Data...\n");
                    //dbg("general", "RTT: %d\n", rtt);
                    call ReadTimer.startPeriodicAt(5000, 7000);
                    break;
                }

                //The client is recieving an ack
                if (mySocket.state == ESTABLISHED)
                {
                    call socketHash.remove(fileD);
                    mySocket.lastAck = ((tcpPack -> seq) - 1); //- mySocket.seqStart);
                    mySocket.lastAck = mySocket.lastAck % 128;

                    dbg("general", "Last Ack = %d, seqStart = %d, seq = %d\n", mySocket.lastAck, mySocket.seqStart, tcpPack -> seq);

                    mySocket.effectiveWindow = tcpPack -> window;
                    call socketHash.insert(fileD, mySocket);
                    for (i = 0; i < 3; i++)
                        call Transport.dataSend(fileD);
                    
                }

                if (mySocket.state == 6)
                {
                    call Transport.close(fileD);
                }
                

                break;

            case 4: //FIN
                dbg("general", "FIN Received\n");
                fileD = findPort(tcpPack -> destPort);
                mySocket = call socketHash.get(fileD);
                if (mySocket.state == 2)
                {    
                    mySocket.state = 5;
                    call Transport.buildPack(&mySocket, confirmedTable, 6, 0);
                    call socketHash.remove(fileD);
                    call socketHash.insert(fileD, mySocket);
                    //call Transport.close(fileD);
                }

                else if (mySocket.state == 6)
                    dbg("general", "Initiating Close\n");
                    call Transport.close(fileD);
                
                break;

            case 5: //DATA

                dbg("general", "DATA Received\n");
                //find fd using this port
                fileD = findPort(tcpPack -> destPort);
                 dbg("general", "FileD: %d   Port: %d\n", fileD, tcpPack->destPort);
                mySocket = call socketHash.get(fileD);
                //if not established yet, send back a SYN_ACK packet to tell it you never recieved ack.
                if(mySocket.state == SYN_SENT)
                {
                    call Transport.buildPack(&mySocket, confirmedTable, 2, mySocket.effectiveWindow);
                    break;
                }

                if (mySocket.state == ESTABLISHED)
                {
                    //server is ready to take data, push to buffer
                    dbg("general", "Storing DATA        window = %d\n", tcpPack->window);
                    printf("Stored = %d\n",call Transport.storeData(fileD, tcpPack -> payload, tcpPack->window));
                }

                break;

            case 6: //FIN_ACK
                
                fileD = findPort(tcpPack -> destPort);
                dbg("general", "FIN_ACK Received    FD = %d\n", fileD);
                //fileD = findPort(tcpPack -> destPort);
                call Transport.close(fileD);

                break;

            default:    //anything else
                dbg("general", "FLAG INVALID\n");
                break;


        }

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
            synSocket.seqStart = seq;
            //make a tcp packet, then add the header of the "IP" layer
            dbg("general", "Getting TCP Package Ready\n");
            makeTCPPack(&tcpPayload, synSocket.src, addr->port, seq, 1, 0, tcpPayload.payload, sizeof(tcpPayload.payload));
            makePack(&sendPackage, TOS_NODE_ID, synSocket.dest.addr, MAX_TTL, PROTOCOL_TCP, call sequencer.getSeq(), &tcpPayload, sizeof(tcpPayload));
            call Sender.send(sendPackage, getTableIndex(&confirmedTable, synSocket.dest.addr).hopTo);
            //rttStart = call TimeoutTimer.getNow();
            //dbg("general", "Starting rtt\n");
            dbg("general", "TCP Package Sent. Seq: %d\n",call sequencer.getSeq());
            call sequencer.updateSeq();
            synSocket.state = SYN_SENT;
            call socketHash.remove(fd);
            call socketHash.insert(fd, synSocket);
            dbg("general", "FileD: %d\n", fd);
            clientFD[fd] = TRUE;
            call WriteTimer.startOneShot(0);
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
        socket_store_t mySocket;
        int i = 0;
        if (call socketHash.contains(fd))
            mySocket = call socketHash.get(fd);
        else  dbg("general", "Couldnt Find FD\n");

         dbg("general", "Close: %d\n", mySocket.state);
        switch (mySocket.state)
        {
            //if established, move to fin_wait_1
            case 2:
                mySocket.state = 6;
                dbg("general","FIN_WAIT_1 intiated\n");
                call WriteTimer.stop();
                call socketHash.remove(fd);
                call socketHash.insert(fd, mySocket);

            break;

            //if close_wait, move to last_ack
            case 5:
                dbg("general","Last_ACK intiated\n");
                mySocket.state = 9;
                call socketHash.remove(fd);
                call socketHash.insert(fd, mySocket);
            break;

            //if fin_wait_1, move to fin_wait_2
            case 6:
                dbg("general","FIN_WAIT_2 intiated\n");
                mySocket.state = 7;
                call socketHash.remove(fd);
                call socketHash.insert(fd, mySocket);
            break;

            //if fin_wait_2, move to time_wait
            case 7:
                 dbg("general","TIME_WAIT intiated\n");
                mySocket.state = 8;
                call socketHash.remove(fd);
                call socketHash.insert(fd, mySocket);
                call CloseTimer.startOneShot(5000);
            break;

            //if time_wait, move to closed
            case 8:
                //Set client socket free, free the used ports and fd.
                //may shut down entire client if it doesn't have another socket.
                dbg("general","Client Close intiated\n");
                mySocket.state = 0;
                for (i = 0; i < call bookedPorts.size(); i++)
                {
                    if (mySocket.src == call bookedPorts.get(i))
                    {
                        call bookedPorts.remove(i);
                        break;
                    }
                }
                call socketHash.remove(fd);
                clientFD[fd] = FALSE;
                dbg("general", "Client Socket Closed\n");
                //call socketHash.insert(fd, mySocket);
            break;

            //if last_ack, move to closed
            case 9:
                //Set server socket free, free the used ports and fd 
                //server won't completely shut down as it still has a listen socket.
                dbg("general","Server Close intiated\n");
                mySocket.state = 0;
                for (i = 0; i < call bookedPorts.size(); i++)
                {
                    if (mySocket.src == call bookedPorts.get(i))
                    {
                        call bookedPorts.remove(i);
                        break;
                    }
                }
                call socketHash.remove(fd);
                serverFD[fd] = FALSE;
                dbg("general", "Server Socket Closed\n");
                //call socketHash.insert(fd, mySocket);
            break;


            default:

            break;
        }
      


      

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