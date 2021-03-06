key me = NULL_KEY;
integer read_chan = 0;
integer write_chan = 0;
key listen_key = NULL_KEY;

integer FN_PRSTR = 105;

string requote(string s) {
    list parts = llParseString2List(s,[],["\\","\""]);
    integer i;
    s = "";
    for (i=0; i < llGetListLength(parts); i++) {
        string part = llList2String(parts,i);
        if (part == "\\") s += "\\\\";
        else if (part == "\"") s += "\\\"";
        else s += part;
    }
    return "\""+s+"\"";
}

//////////// MESSAGES /////////////////////////

string json_obj(list parts) {
    return llList2Json(JSON_OBJECT, parts);
}

string json_array(list l) {
    return llList2Json(JSON_ARRAY, l);
}

// MSG_PARSE_REQ format: string
integer MSG_PARSE_REQ = 0;

// MSG_PARSE_RESP format: {"success?":<boolean>,"data":<string or form>}
integer MSG_PARSE_RESP = 1;

// MSG_NATIVE_REQ: {"tag":<string>, "native_id": <integer>, "args": <array>}
integer MSG_NATIVE_REQ = 6;

send_native_req(string tag, integer id, list args) {
    string r = json_obj(["tag", tag, "native_id", id, "args", json_array(args)]);
    llMessageLinked(LINK_THIS, MSG_NATIVE_REQ, r, me);
}

// MSG_NATIVE_RESP: {"tag":<string>, "success?": <boolean>, "data": <form or string>}
integer MSG_NATIVE_RESP = 7;

///////////////// REPL /////////////////////////

integer succeeded(string msg) {
    return JSON_TRUE == llJsonValueType(msg, ["success?"]);
}

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
                state eval;
            }
        }
        if (name == "MAL HTTP Bridge") {
            listen_key = id;
            llOwnerSay("Accepting commands from "+(string)id);
            state default;
        }
    }    
}

state eval
{
    state_entry()
    {
        if (listen_key != NULL_KEY) {
            llListen(read_chan, "", listen_key, "");
        }
        llMessageLinked(LINK_THIS, MSG_PARSE_REQ, input, me);
    }
    
    touch(integer num)
    {
        state read;
    }
    
    listen(integer chan, string name, key id, string message)
    {
        if ("," == llGetSubString(message, 0, 0)) {
            input = llGetSubString(message,1,-1);
            if (input=="exit") {
                llOwnerSay("Goodbye.");
                llDie();
            }
        }
    }
    
    link_message(integer sender, integer num, string str, key id)
    {
        if (me == id) return;
        string data = llJsonGetValue(str,["data"]);
        string tag = llJsonGetValue(str,["tag"]);
        if (num == MSG_PARSE_RESP) {
            if (succeeded(str)) {
                if (JSON_STRING == llJsonValueType(str,["data"]))
                    data = requote(data);
                list args = llJson2List(llJsonSetValue("[]",[JSON_APPEND],data));
                llOwnerSay("repl: pr-str args="+llList2Json(JSON_ARRAY, args));
                send_native_req("repl", FN_PRSTR, args);
            } else {
                llSay(write_chan, "repl: parse failed: "+data);
                state read;
            }
        } else if (num == MSG_NATIVE_RESP && tag == "repl") {
            llOwnerSay("repl: pr-str resp: "+str);
            llSay(write_chan, data);
            state read;
        }
    }
}