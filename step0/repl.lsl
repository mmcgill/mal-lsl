key me = NULL_KEY;
integer read_chan = 0;
integer write_chan = 0;
key listen_key = NULL_KEY;

///////////////// REPL /////////////////////////

string input;

default
{
    state_entry()
    {
        if (me == NULL_KEY) me = llGenerateKey();
        llOwnerSay("repl: ready ("+(string)llGetFreeMemory()+")");
        state read;
    }
}

state read
{
    state_entry()
    {
        llOwnerSay("repl: read");
        llListen(read_chan, "", llGetOwner(), "");
        if (listen_key != NULL_KEY) {
            llListen(read_chan, "", listen_key, "");
        }
    }
    
    on_rez(integer param)
    {
        llOwnerSay("Rezzed, responding on "+(string)param);
        read_chan = param;
        write_chan = param;
        if (param != 0)
            llListen(param,"MAL HTTP Bridge",NULL_KEY,"ack");
        else
            state default;
        llSay(param,"ready");
    }

    listen(integer chan, string name, key id, string message)
    {
//        llOwnerSay("repl: chan="+(string)chan+" name="+name+" key="+(string)id+" msg="+message);
        if (chan == read_chan) {
            if ("," == llGetSubString(message, 0, 0)) {
                input = llGetSubString(message,1,-1);
                if (input=="exit") {
                    llOwnerSay("Goodbye.");
                    llDie();
                }
                llSay(write_chan, input);
            }
        }
        if (name == "MAL HTTP Bridge") {
            listen_key = id;
            llOwnerSay("Accepting commands from "+(string)id);
            state default;
        }
    }    
}