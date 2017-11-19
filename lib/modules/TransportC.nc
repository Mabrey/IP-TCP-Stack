#include "../../includes/socket.h"

configuration TransportC
{
    provides interface Transport;
}

implementation
{
    components TransportP;
    Transport = TransportP;

    components new HashmapC(socket_store_t, 10) as socketHashC;
    TransportP.socketHash -> socketHashC;

    components new ListC(socket_port_t, 10) as bookedPortsC;
    TransportP.bookedPorts -> bookedPortsC;

}