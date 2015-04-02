/* DESIGN SKETCH
 * The REPL prompts for input, messages the parser to parse the input,
 * messages the evaluator to evaluate the input, messages the evaluator
 * again to print the result, and displays that result to the user.
 * It also keeps a history of inputs and results.
 */

key me = NULL_KEY;
integer read_chan = -34;

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

// MSG_EVAL_REQ: {"tag:":<string>,"data":<form>}
integer MSG_EVAL_REQ = 2;
string eval_req(string tag, string data) {
    string r = "{}";
    r = llJsonSetValue(r,["tag"], tag);
    r = llJsonSetValue(r,["data"], data);
    return r;
}

// MSG_EVAL_RESP: {"tag:"<string>,"success?":<boolean>,"data":<string or form>}
integer MSG_EVAL_RESP = 3;

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

READ() {
    llOwnerSay("repl: loop");
    llListen(read_chan, "", llGetOwner(), "");
    llTextBox(llGetOwner(), "user> ", read_chan);
}

default
{
    state_entry()
    {
        if (me == NULL_KEY) me = llGenerateKey();
        llOwnerSay("repl: waiting");
    }

    touch_start(integer total_number)
    {
        // only owner can trigger the REPL
        if (llGetOwner() != llDetectedKey(0)) return;
        state loop;
    }
}

state loop
{
    state_entry()
    {
        READ();
    }
    
    touch(integer num)
    {
        READ();
    }
    
    listen(integer chan, string name, key id, string message)
    {
        llMessageLinked(LINK_THIS, MSG_PARSE_REQ, message, me);
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
                string req = eval_req("eval1", data);
                llOwnerSay("repl: eval_req: "+req);
                llMessageLinked(LINK_THIS, MSG_EVAL_REQ, req, me);
            } else {
                llOwnerSay("repl: parse failed: "+data);
            }
        } else if (num == MSG_EVAL_RESP) {
            if (succeeded(str)) {
                if (JSON_STRING == llJsonValueType(str,["data"]))
                    data = requote(data);
                llOwnerSay("repl: eval resp: "+str);
                llOwnerSay("repl: eval result: "+data);
                list args = llJson2List(llJsonSetValue("[]",[JSON_APPEND],data));
                llOwnerSay("repl: pr-str args="+llList2Json(JSON_ARRAY, args));
                send_native_req("repl", FN_PRSTR, args);
            } else {
                llOwnerSay("repl: eval failed: "+data);
                READ();
            }
        } else if (num == MSG_NATIVE_RESP && tag == "repl") {
            // in this case we're getting back a string form, but we want to
            // print it, so we don't add quotes
//            if (JSON_STRING == llJsonValueType(str,["data"]))
//                data = "\""+data+"\"";
            llOwnerSay("repl: pr-str resp: "+str);
            llOwnerSay("repl: "+data);
            READ();
        }
    }
}