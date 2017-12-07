/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"

configuration NodeC{
}
implementation {
    components MainC;
    components Node;
    components new AMReceiverC(AM_PACK) as GeneralReceive;
    components new TimerMilliC() as NodeTimerC;
    components new TimerMilliC() as LSPNodeTimerC;
    components new TimerMilliC() as dijkstraTimerC;
    components new TimerMilliC() as TimeoutTimerC;
    components new TimerMilliC() as WriteTimerC;
    components new TimerMilliC() as ReadTimerC;
    components new TimerMilliC() as CloseTimerC;
    
   

    Node -> MainC.Boot;
    Node.Receive -> GeneralReceive;

    Node.NodeTimer-> NodeTimerC;
    Node.LSPNodeTimer -> LSPNodeTimerC;
    Node.dijkstraTimer -> dijkstraTimerC;
    TransportP.TimeoutTimer -> TimeoutTimerC;
    TransportP.WriteTimer -> WriteTimerC;
    TransportP.ReadTimer -> ReadTimerC;
    TransportP.CloseTimer -> CloseTimerC;

    components TransportP;
    Node.Transport -> TransportP;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;
    TransportP.Sender -> SimpleSendC;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;

    components new ListC(pack,64) as packListC;            //create a list for packets
    Node.packList->packListC;
    TransportP.packList -> packListC;

    components new HashmapC(socket_store_t, 10) as socketHashC;
    Node.socketHash -> socketHashC;
    TransportP.socketHash -> socketHashC;

    components new ListC(socket_port_t, 10) as bookedPortsC;
    TransportP.bookedPorts -> bookedPortsC;
   
    //components new ListC(neighbor*,64) as neighborListC;   //create a list for neighbors
   // Node.neighborList->neighborListC;

   // components new PoolC(neighbor, 64) as neighborPoolC;
   // Node.neighborPool -> neighborPoolC;

    components RandomC as Random;
    Node.Random -> Random;
    TransportP.Random -> Random;

    components sequencerC;
    Node.sequencer -> sequencerC;
    TransportP.sequencer -> sequencerC;

    //components TransportC;
    //Node.Transport -> TransportC;
}