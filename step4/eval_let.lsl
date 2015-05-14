key me = NULL_KEY;

// tags for forms
integer LIST = 0;
integer SYMBOL = 1;
integer KEYWORD = 2;
integer VECTOR = 3;
integer HASHMAP = 5;

string GLOBAL_ENV = "GLOBAL";

string tag = "";
string form = "";
integer pr_str_result = 0;

integer msg_type;
string msg;

integer eval_error = 0;
string eval_error_message = "";

string set_eval_error(string msg) {
    eval_error = TRUE;
    eval_error_message = msg;
    return "";
}

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

string read_form(list path) {
    if (JSON_STRING == llJsonValueType(form,path))
        return requote(llJsonGetValue(form,path));
    else
        return llJsonGetValue(form,path);
}

// We use an explicit stack so we can always pause computation to send a signal,
// and then resume at the same place when the signal is received.
// We must effectively write eval() as a state machine.
list stack = [];

push(string step) {
//    llOwnerSay("  PUSH: "+llJsonGetValue(step,["s"]));
    stack = [step]+stack;
}

string peek() {
    return llList2String(stack,0);
}

string pop() {
    string s = peek();
    stack = llDeleteSubList(stack,0,0);
//    llOwnerSay("  POP: "+llJsonGetValue(s,["s"]));
    return s;
}

update(string step) {
    stack = llListReplaceList(stack, [step], 0, 0);
}

integer is_empty() {
    return 0 == llGetListLength(stack);    
}

dump_stack() {
    string s;
    integer i;
    for (i=0; i < llGetListLength(stack); i++) {
        s+=" "+llJsonGetValue(llList2String(stack,i),["s"]);
    }
    llOwnerSay("   STACK: ["+s+"]");
}

string json_obj(list parts) {
    return llList2Json(JSON_OBJECT, parts);
}

string json_array(list l) {
    return llList2Json(JSON_ARRAY, l);
}

////////// MESSAGES ////////////////

// MSG_EVAL_REQ: {"tag:":<string>, "data":<form>, "env_id": <string>, "path": <list of strings>}
integer MSG_EVAL_REQ = 2;
send_eval_req(string tag, list path,string env_id) {
    string req = json_obj(["tag", tag, "env_id", env_id, "path", json_array(path)]);
    req = llJsonSetValue(req,["data"],form);
    llMessageLinked(LINK_THIS, MSG_EVAL_REQ, req, me);
}

// MSG_EVAL_RESP: {"tag:"<string>,"success?":<boolean>,"data":<string or form>}
integer MSG_EVAL_RESP = 3;

// MSG_LOOKUP_REQ: {"tag": <string>, "env_id": <string>, "symbol":<string>}
integer MSG_LOOKUP_REQ = 4;
send_lookup(string env_id, string symbol, string tag) {
    string req = llList2Json(JSON_OBJECT, ["env_id", env_id, "symbol", symbol, "tag", tag]);
    llMessageLinked(LINK_THIS, MSG_LOOKUP_REQ, req, me);
}

// MSG_LOOKUP_RESP: {"tag": <string>, "success?": <boolean>, "data":<string or form>}
integer MSG_LOOKUP_RESP = 5;

// MSG_NATIVE_REQ: {"tag":<string>, "native_id": <integer>, "args": <array>}
integer MSG_NATIVE_REQ = 6;

send_native_req(string tag, integer id, list args) {
    string r = json_obj(["tag", tag, "native_id", id, "args", json_array(args)]);
    llMessageLinked(LINK_THIS, MSG_NATIVE_REQ, r, me);
}

// MSG_NATIVE_RESP: {"tag":<string>, "success?": <boolean>, "data": <form or string>}
integer MSG_NATIVE_RESP = 7;


// MSG_ENV_CREATE_REQ: {"tag": <string>, "outer_id": <string>, "binds": <list of names>, "args", <list of values>}
integer MSG_ENV_CREATE_REQ = 8;
send_env_create_req(string tag, string outer_id, list binds, list args) {
    string r = json_obj(["tag", tag, "outer_id", outer_id,"binds", json_array(binds), "args", json_array(args)]);
    llMessageLinked(LINK_THIS, MSG_ENV_CREATE_REQ, r, me);
}

// MSG_ENV_CREATE_RESP: {"tag": <string>, "data": <string>}
integer MSG_ENV_CREATE_RESP = 9;

/*
// MSG_ENV_DELETE_REQ: {"tag": <string>, "env_id": <string>}
integer MSG_ENV_DELETE_REQ = 10;
send_env_delete_req(string tag, string env_id) {
    string r = json_obj(["tag", tag, "env_id", env_id]);
    llMessageLinked(LINK_THIS, MSG_ENV_DELETE_REQ, r, me);
}

// MSG_ENV_DELETE_RESP: {"tag": <string>}
integer MSG_ENV_DELETE_RESP = 11;
*/

// MSG_ENV_SET_REQ: {"tag": <string>, "env_id": <string>, "symbol": <string>, "data": <form>}
integer MSG_ENV_SET_REQ = 12;
send_env_set_req(string tag, string env_id, string symbol, string form) {
    string r = json_obj(["tag", tag, "env_id", env_id, "symbol", symbol]);
    r=llJsonSetValue(r,["data"],form);
    llMessageLinked(LINK_THIS, MSG_ENV_SET_REQ, r, me);
}

// MSG_ENV_SET_RESP: {"tag": <string>}
integer MSG_ENV_SET_RESP = 13;

// MSG_ENV_INCREF_REQ: {"tag": <string>, "env_id": <string>}
integer MSG_ENV_INCREF_REQ = 14;
send_env_incref_req(string tag, string env_id) {
    string r = json_obj(["tag", tag, "env_id", env_id]);
    llMessageLinked(LINK_THIS, MSG_ENV_INCREF_REQ, r, me);
}

// MSG_ENV_INCREF_RESP: {"tag": <string>}
integer MSG_ENV_INCREF_RESP = 15;

// MSG_ENV_DECREF_REQ: {"tag": <string>, "env_id": <string>}
integer MSG_ENV_DECREF_REQ = 16;
send_env_decref_req(string tag, string env_id) {
    string r = json_obj(["tag", tag, "env_id", env_id]);
    llMessageLinked(LINK_THIS, MSG_ENV_DECREF_REQ, r, me);
}

// MSG_ENV_DECREF_RESP: {"tag": <string>}
integer MSG_ENV_DECREF_RESP = 17;

// MSG_EVAL_LET_REQ: {"tag:":<string>,"data":<form>, "path": <list of strings>, "env_id": <string>}
integer MSG_EVAL_LET_REQ = 18;

// run results
integer WAIT = 0;
integer DONE = 1;
integer GO = 2;


integer LET = 5;
string let(list path, string env_id) {
    return json_obj(["s", LET, 
                     "n", "start",
                     "path", json_array(path), 
                     "env_id", env_id]);
}

integer do_let(string s) {
    string n = llJsonGetValue(s,["n"]);
    list path = llJson2List(llJsonGetValue(s,["path"]));
    string env_id = llJsonGetValue(s,["env_id"]);
    string new_env_id = llJsonGetValue(s,["new_env_id"]);
    integer i = (integer)llJsonGetValue(s,["i"]);
    if (n == "start") {
        string bindings = llJsonGetValue(form, path+2);
        
        if (JSON_INVALID == bindings || JSON_INVALID == llJsonGetValue(form, path+3)) {
            set_eval_error("def! requires two args");
            return DONE;
        }
        if (JSON_ARRAY != llJsonValueType(bindings, []) || (LIST != (integer)llJsonGetValue(bindings, [0]) &&
                                                            VECTOR != (integer)llJsonGetValue(bindings, [0]))) {
            set_eval_error("let* binding argument must be a list");
            return DONE;
        }
        update(llJsonSetValue(s,["n"],"after_create"));
        send_env_create_req("let_after_create", env_id, [], []);
        return WAIT;
    }        
    if (n == "after_create") {
//        llOwnerSay("eval_let: environment created");
        new_env_id = llJsonGetValue(msg, ["data"]);
        s = llJsonSetValue(s, ["new_env_id"], new_env_id);
        i = 1;
        s = llJsonSetValue(s, ["i"], "1");
        n = "after_set";  
    }
    if (n == "after_eval") {
        tag = llJsonGetValue(s,["tag"]);
        if (JSON_FALSE == llJsonGetValue(msg,["success?"])) {
            set_eval_error(llJsonGetValue(msg,["data"]));
            return DONE;
        }
        form = llJsonGetValue(msg,["data"]);
        if (JSON_STRING == llJsonValueType(msg,["data"]))
            form = requote(form);
        string result = llJsonGetValue(form,path+[2,(i+1)]);
        if (JSON_STRING == llJsonValueType(form,path+[2,(i+1)]))
            result = requote(result);
        string sym = llJsonGetValue(form,path+[2,i,1]);
//        llOwnerSay("eval_let: arg evaluated ("+sym+"="+result+")");
        s=llJsonSetValue(s,["n"],"after_set");
        s=llJsonSetValue(s,["i"],(string)(i+2));
        if (JSON_OBJECT == llJsonValueType(result,[]) && JSON_INVALID == llJsonValueType(result,["id"])) {
            // we've 'consumed' a closure, so we need to decref after we set
            s=llJsonSetValue(s,["decref"],llJsonGetValue(result,["env_id"]));
        }
        update(s);
        send_env_set_req("let_after_set", new_env_id, sym, result);
        return WAIT;
    }
    if (n == "after_set") {
//        llOwnerSay("eval_let: arg set");
        string decref = llJsonGetValue(s,["decref"]);
        if (JSON_INVALID != decref) {
            send_env_decref_req("let_after_decref", decref);
            update(llJsonSetValue(s,["n"],"after_decref"));
            return WAIT;
        } else {
            n="after_decref";
        }
    }
    if (n == "after_decref") {
        s=llJsonSetValue(s,["tag"],tag);
        if (JSON_INVALID == llJsonValueType(form,path+[2,i])) {
            update(llJsonSetValue(s,["n"],"delete_env"));
            string expr = llJsonGetValue(form,path+3);
            if (JSON_STRING == llJsonValueType(form,path+3))
                expr = requote(expr);
            form = llJsonSetValue(form,path,expr);
            // push(eval(path,new_env_id));
            send_eval_req("let_delete_env", path,new_env_id);
        } else {
            s = llJsonSetValue(s, ["n"], "after_eval");
            update(s);
            // push(eval(path+[2,(i+1)],new_env_id));
            send_eval_req("let_after_eval", path+[2,(i+1)],new_env_id);
        }
        return WAIT;
    }
    if (n == "delete_env") {
//        llOwnerSay("eval: let: delete env");
        update(llJsonSetValue(s,["n"],"let_end"));
        tag = llJsonGetValue(s,["tag"]);
        if (JSON_FALSE == llJsonGetValue(msg,["success?"])) {
            set_eval_error(llJsonGetValue(msg,["data"]));
            return DONE;
        }
        form = llJsonGetValue(msg,["data"]);
        if (JSON_STRING == llJsonValueType(msg,["data"]))
            form = requote(form);        
        
        send_env_decref_req("let_delete_env", new_env_id);
        return WAIT;
    }
    if (n == "let_end") {
        pop();
        return DONE;
    }
    set_eval_error("Unrecognized let* step: "+n);
    return DONE;    
}

integer run() {
    integer status = GO;
    while (!is_empty() && status == GO) {
        string step = peek();
        integer step_code = (integer)llJsonGetValue(step,["s"]);
//        llOwnerSay(" step: "+step+" ("+(string)llGetFreeMemory()+")");
//        llOwnerSay(" form: "+form);
//        llOwnerSay(" tag: "+tag);
        //dump_stack();
        if (step_code == LET)      status = do_let(step);
        else {
            set_eval_error("invalid step code: "+(string)step_code);
            status = DONE;
        }
        //dump_stack();
    }
    if (is_empty()) {
        return DONE;
    } else {
        return status;
    }
}

integer continue() {
    if (DONE == run()) {
        string resp;
        if (eval_error) {
//            llOwnerSay("eval_let: failed: "+eval_error_message);
            resp = json_obj(["tag", tag, "success?", JSON_FALSE, "data", eval_error_message]);
            eval_error = 0;
            eval_error_message = "";
            pop();
        } else {
//            llOwnerSay("eval_let: finished: "+ form);
            resp = json_obj(["tag", tag, "success?", JSON_TRUE]);
            resp = llJsonSetValue(resp,["data"],form);
        }
        llMessageLinked(LINK_THIS, MSG_EVAL_RESP, resp, me);
        return DONE;
    } else {
        //llOwnerSay("eval_let: waiting");
        return WAIT;
    }
}

default
{
    state_entry()
    {
        if (me == NULL_KEY) me = llGenerateKey();
        eval_error = 0;
        eval_error_message = "";
        form = "";
        tag = "";
        msg = "";
        stack = [];
        llOwnerSay("eval_let: ready ("+(string)llGetFreeMemory()+")");
    }
     
    link_message(integer sender, integer num, string str, key id)
    {
        if (me == id) return;
        string _tag = llJsonGetValue(str,["tag"]);
        if (num == MSG_EVAL_LET_REQ) {
            llOwnerSay("eval_let: starting");
            tag = _tag;
            string env_id = llJsonGetValue(str,["env_id"]);
            form = llJsonGetValue(str,["form"]);
            if (JSON_STRING == llJsonValueType(str,["form"]))
                form = requote(form);
            list path = llJson2List(llJsonGetValue(str,["path"]));
            push(let(path,env_id));
            continue();
        } else if ("let_" == llGetSubString(_tag, 0, 3)) {
            llOwnerSay("eval_let: continuing");
            msg_type = num;
            msg = str;
            if (JSON_INVALID != llJsonValueType(str,["form"])) {
                form = llJsonGetValue(str,["form"]);
                if (JSON_STRING == llJsonValueType(str,["form"]))
                    form = requote(form);
            }
            continue();
        }
    }
}
