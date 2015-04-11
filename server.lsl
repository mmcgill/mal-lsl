integer chan = 3434;
integer next_repl_chan = 5872311;

string url;
key url_req;

string repl_map = "{}";
string rez_map = "{}";
string eval_map = "{}"; // listen chan -> repl id

say_info() {
    llOwnerSay("Chat channel: "+(string)chan);
    llOwnerSay("URL: "+url);
}

default
{
    state_entry()
    {
        llSetTimerEvent(0);
        state stopped;
    }
}

state running
{
    state_entry()
    {
        llOwnerSay("Starting");
        url_req = llRequestURL();
        llListen(chan,"",llGetOwner(), "stop");
        llSetTimerEvent(1);
    }
    
    http_request(key id, string method, string body)
    {
        if (method == URL_REQUEST_DENIED) {
            llOwnerSay("Failed to get URL: "+body);
            state stopped;
            return;
        }
        if (method == URL_REQUEST_GRANTED) {
            url = body;
            llOwnerSay("Started at "+url);
            return;
        }
        
        
        
        string path = llGetHTTPHeader(id,"x-path-info");
        llOwnerSay("HTTP: method="+method+" path="+path);
        list segments = llParseString2List(path,["/"],[]);
        integer num_segments = llGetListLength(segments);
        if (num_segments > 1) {
            llHTTPResponse(id, 404, "Not found (Invalid URL)");
            return;
        }
        string repl_id;
        if (num_segments == 1) {
            repl_id = llList2String(segments,0);
            llOwnerSay("HTTP:  repl_id="+repl_id);
        }
        if (method == "GET") {
            if (num_segments == 0) {
                list repl_list = llJson2List(repl_map);
                integer i;
                string s = "[]";
                for (i=1; i < llGetListLength(repl_list); i+=2) {
                    s = llJsonSetValue(s,[JSON_APPEND],llList2String(repl_list,i));
                }
                llHTTPResponse(id, 200, s);
                return;
            }
            if (JSON_INVALID != llJsonValueType(repl_map,[repl_id])) {
                string repl = llJsonGetValue(repl_map,[repl_id]);
                llHTTPResponse(id, 200, repl);
                return;
            }
        }
        if (method == "POST") {
            if ("" == path || "/" == path) {                
                integer repl_chan = next_repl_chan;
                next_repl_chan++;
                integer listen_handle = llListen(repl_chan, "MAL REPL", NULL_KEY, "ready");
                string rez = "{}";
                rez = llJsonSetValue(rez,["t"],(string)llGetTime());
                rez = llJsonSetValue(rez,["req"],(string)id);
                rez = llJsonSetValue(rez,["listen"],(string)listen_handle);
                rez_map = llJsonSetValue(rez_map,[(string)repl_chan],rez);
                vector offset = <1,0,0>*llEuler2Rot(<0,0,llFrand(360)>*DEG_TO_RAD);
                llRezAtRoot("MAL REPL",llGetPos()+offset,ZERO_VECTOR,ZERO_ROTATION,repl_chan);
                return;
            }
            if (JSON_INVALID != llJsonValueType(repl_map,[repl_id])) {
                string repl = llJsonGetValue(repl_map,[repl_id]);
                string repl_state = llJsonGetValue(repl,["state"]);
                if (repl_state != "ready") {
                    llHTTPResponse(id, 400, "REPL is not ready");
                    return;
                }
                integer repl_chan = (integer)llJsonGetValue(repl,["chan"]);
                llOwnerSay("listening for eval response on "+(string)repl_chan);
                repl = llJsonSetValue(repl,["state"],"evaluating");
                repl = llJsonSetValue(repl,["t"],(string)llGetTime());
                if (JSON_INVALID != llJsonValueType(repl,["result"])) {
                    repl = llJsonSetValue(repl,["result"],JSON_DELETE);
                }
                integer listen_handle = llListen(repl_chan,"",(key)repl_id,"");
                repl = llJsonSetValue(repl,["listen"],(string)listen_handle);
                repl_map = llJsonSetValue(repl_map,[repl_id],repl);
                eval_map = llJsonSetValue(eval_map,[(string)repl_chan,"repl_id"],repl_id);
                eval_map = llJsonSetValue(eval_map,[(string)repl_chan,"req_id"],(string)id);
                llSay(repl_chan,","+body);
                return;
            }
        }
        if (method == "DELETE") {
            if (JSON_INVALID != llJsonValueType(repl_map,[repl_id])) {
                string repl = llJsonGetValue(repl_map,[repl_id]);
                llOwnerSay("Deleting "+repl);
                integer chan = (integer)llJsonGetValue(repl,["chan"]);
                if (JSON_INVALID != llJsonValueType(repl,["listen"])) {
                    integer listen_handle = (integer)llJsonGetValue(repl,["listen"]);
                    llListenRemove(listen_handle);
                }
                llSay(chan,",exit");
                repl_map = llJsonSetValue(repl_map,[repl_id],JSON_DELETE);
                llHTTPResponse(id,204,"Deleted");
            }
        }
        llHTTPResponse(id, 404, "Not found");
    }
    
    timer()
    {
        // for each entry in the rez map, check for timeout
        list l = llJson2List(rez_map);
        integer i;
//        llOwnerSay("rez_map="+rez_map);
        for (i=1; i < llGetListLength(l); i+=2) {
            string rez = llList2String(l,i);
            float t = (float)llJsonGetValue(rez,["t"]);
            if (llGetTime() - t > 5) {
                integer chan = llList2Integer(l,i-1);
                llOwnerSay("Timed out waiting on channel "+(string)chan);
                integer listen_handle = (integer)llJsonGetValue(rez,["listen"]);
                llListenRemove(listen_handle);
                key req = (key)llJsonGetValue(rez,["req"]);
                llHTTPResponse(req,500,"timed out waiting for rez");
                rez_map = llJsonSetValue(rez_map,[(string)chan],JSON_DELETE);
            }
        }
        // for each entry in the eval map, check to see if we need to respond to a pending POST
        l = llJson2List(eval_map);
        for (i=1; i<llGetListLength(l); i+=2) {
            string entry = llList2String(l,i);
            string repl_id = llJsonGetValue(entry,["repl_id"]);
            if (JSON_INVALID != llJsonValueType(repl_map,[repl_id,"t"])) {
                float t = (float)llJsonGetValue(repl_map,[repl_id,"t"]);
                if (llGetTime() - t > 10) {
                    llOwnerSay("Timed out waiting for eval, sending response");
                    key req_id = (key)llJsonGetValue(entry,["req_id"]);
                    llHTTPResponse(req_id,204,"");
                    repl_map = llJsonSetValue(repl_map,[repl_id,"t"],JSON_DELETE);
                }
            }
        }
    }
    
    touch_start(integer num)
    {
        say_info();
    }
    
    listen(integer channel, string name, key id, string msg)
    {
        llOwnerSay("msg: "+msg);
        if (msg == "stop" && id == llGetOwner()) {
            state stopped;
            return;
        }
        if (JSON_INVALID != llJsonValueType(eval_map,[(string)channel])) {
            string repl_id = llJsonGetValue(eval_map,[(string)channel,"repl_id"]);
            llOwnerSay("Got msg from "+repl_id+": "+msg);
            if (JSON_INVALID != llJsonValueType(eval_map,[(string)channel,"req_id"])) {
                key req_id = (key)llJsonGetValue(eval_map,[(string)channel,"req_id"]);
                llHTTPResponse(req_id,200,msg);
            }
            eval_map = llJsonSetValue(eval_map,[(string)channel],JSON_DELETE);
            repl_map = llJsonSetValue(repl_map,[repl_id,"state"],"ready");
            repl_map = llJsonSetValue(repl_map,[repl_id,"result"],msg);
            integer listen_handle = (integer)llJsonGetValue(repl_map,[repl_id,"listen"]);
            llListenRemove(listen_handle);
            return;
        }
        if (msg == "ready") {
            if (JSON_INVALID == llJsonValueType(rez_map,[channel])) {
                llOwnerSay("Got unexpected 'ready' on chan "+(string)channel);
                llSay(channel,",exit");
                return;
            }
            llOwnerSay("Got 'ready' on chan "+(string)channel);
            llSay(channel,"ack");
            string rez = llJsonGetValue(rez_map,[(string)channel]);
            rez_map = llJsonSetValue(rez_map,[(string)channel],JSON_DELETE);
            key req_id = (key)llJsonGetValue(rez,["req"]);
            integer listen_handle = (integer)llJsonGetValue(rez,["listen"]);
            llListenRemove(listen_handle);
            string repl = "{}";
            repl = llJsonSetValue(repl,["state"],"ready");
            repl = llJsonSetValue(repl,["id"], (string)id);
            repl = llJsonSetValue(repl,["chan"], (string)channel);
            repl_map = llJsonSetValue(repl_map,[(string)id],repl);
            llHTTPResponse(req_id, 200, repl);
            return;
        }
    }
}

state stopped
{
    state_entry()
    {
        llReleaseURL(url);
        llOwnerSay("Stopped");
        llListen(chan,"",llGetOwner(), "start");
    }
    
    touch_start(integer num)
    {
        say_info();
    }
    
    listen(integer channel, string name, key id, string msg)
    {
        state running;
    }
}
