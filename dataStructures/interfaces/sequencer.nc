
//used to handle IP layer sequence number 
//in a global scope
interface sequencer
{
    command uint16_t sequencer.getSeq();
    command void sequencer.updateSeq();
 
}