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
    //components new TimerMilliC() as lspShareTimerC;

    Node -> MainC.Boot;

    Node.Receive -> GeneralReceive;

    Node.NodeTimer-> NodeTimerC;
  //  Node.lspShareTimer -> lspShareTimerC;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;

    components new ListC(pack,64) as packListC;            //create a list for packets
    Node.packList->packListC;
   
    components new ListC(neighbor*,64) as neighborListC;   //create a list for neighbors
    Node.neighborList->neighborListC;

    components new PoolC(neighbor, 64) as neighborPoolC;
    Node.neighborPool -> neighborPoolC;

    components RandomC as Random;
    Node.Random -> Random;
}