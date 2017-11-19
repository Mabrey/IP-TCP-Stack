module sequencerC
{
    provides interface sequencer;
}

implementation
{
    uint16_t sequence = 0;

    command uint16_t sequencer.getSeq()
    {
        return sequence;
    }

    command void sequencer.updateSeq()
    {
        sequence++;
    }
}