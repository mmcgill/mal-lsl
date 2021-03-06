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

////////// MESSAGES ////////////////

// MSG_EVAL_REQ: {"tag:":<string>,"data":<form>, "pr-str": <boolean>}
integer MSG_EVAL_REQ = 2;

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

///////////// STEPS ////////////////

string json_obj(list parts) {
    return llList2Json(JSON_OBJECT, parts);
}

string json_array(list l) {
    return llList2Json(JSON_ARRAY, l);
}

integer EVAL = 0;

string eval(list path,string env_id) {
    return json_obj(["s",    (string)EVAL, 
                     "n",    "start", 
                     "path", json_array(path),
                     "env_id", env_id]);
}

integer do_eval(string s) {
    string n = llJsonGetValue(s,["n"]);
    list path = llJson2List(llJsonGetValue(s,["path"]));
    string env_id = llJsonGetValue(s,["env_id"]);
    if (n == "start") {
        update(llJsonSetValue(s,["n"], "after_ast"));
        push(eval_ast(path, env_id));
        return GO;
    }
    if (n == "after_ast") {
        pop();
        string type = llJsonValueType(form,path);
        if (JSON_ARRAY == type) {
            integer tag = (integer)llJsonGetValue(form,path+0);
            if (LIST == tag) {
                push(apply(path));                
            }
        }
        return GO;
    }
    set_eval_error("Unrecognized eval step: "+n);
    return DONE;
}

integer EVAL_AST = 1;
string eval_ast(list path, string env_id) {
    return json_obj(["s",    (string)EVAL_AST,
                     "n",    "start",
                     "path", json_array(path),
                     "env_id", env_id]);
}

integer do_eval_ast(string s) {
    string n = llJsonGetValue(s,["n"]);
    list path = llJson2List(llJsonGetValue(s,["path"]));
    string env_id = llJsonGetValue(s,["env_id"]);
    if (n == "start") {
        string type = llJsonValueType(form,path);
        if (JSON_ARRAY == type) {
            integer tag = (integer)llJsonGetValue(form,path+0);
            if (SYMBOL == tag) {
                string symbol = llJsonGetValue(form, path+1);
                // look up symbol in environment
                update(llJsonSetValue(s,["n"],"after_symbol_lookup"));
                send_lookup(env_id, symbol, "after_symbol_lookup");
                return WAIT;
            } else if (LIST == tag || VECTOR == tag) {
                // evaluate each child
                s = llJsonSetValue(s,["n"], "children");
                s = llJsonSetValue(s,["i"], "1");
                update(s);
                return GO;
            } else if (HASHMAP == tag) {
                s = llJsonSetValue(s,["n"], "mapvals");
                s = llJsonSetValue(s,["i"], "0");
                update(s);
                return GO;
            }
            set_eval_error("Unevaluatable form "+llJsonGetValue(form,path));
            return DONE;
        }
        pop();
        return GO;
    }
    if (n == "after_symbol_lookup") {
        if (msg_type != MSG_LOOKUP_RESP) {
            set_eval_error("eval_ast: unexpected message "+msg);
            return DONE;
        }
        string tag = llJsonGetValue(msg,["tag"]);
        string success = llJsonGetValue(msg, ["success?"]);
        string data = llJsonGetValue(msg,["data"]);
        if (success == JSON_TRUE) {
            if (JSON_STRING == llJsonValueType(msg,["data"]))
                data = requote(data);
//            llOwnerSay("eval: eval_ast: after_symbol_lookup: data="+data);
            form = llJsonSetValue(form, path, data);
            pop();
            return GO;
        } else {
            set_eval_error("Undefined symbol "+llJsonGetValue(form, path+1));
            return DONE;
        }
    }
    if (n == "children") {
        integer i = (integer)llJsonGetValue(s, ["i"]);
        if (JSON_INVALID != llJsonValueType(form,path+i)) {
            update(llJsonSetValue(s, ["i"], (string)(i+1)));
            push(eval(path+i, env_id));
        } else {
            pop();
        }
        return GO;
    }
    if (n == "mapvals") {
        integer i = (integer)llJsonGetValue(s, ["i"]);
        list map = llJson2List(llJsonGetValue(form,path+[1]));
        if (i < llGetListLength(map)) {
            string k = llList2String(map,i);
//            llOwnerSay("eval: apply_ast: k="+k);
            update(llJsonSetValue(s, ["i"], (string)(i+2)));
            push(eval(path+[1,k], env_id));
        } else {
            pop();
        }
        return GO;
    }
    set_eval_error("Unrecognized eval_ast step: "+n);
    return DONE;
}

integer APPLY = 2;
string apply(list path) {
    return json_obj(["s",    (string)APPLY,
                     "n",    "start",
                     "i",    2,
                     "path", json_array(path)]);
}

list validate_args(list binds,list path) {
    integer i=2;
    list args = llDeleteSubList(llJson2List(llJsonGetValue(form,path)),0,1);
    integer num_args = llGetListLength(args);
    integer num_binds = llGetListLength(binds);
//    llOwnerSay("apply:num_args="+(string)num_args+" num_binds="+(string)num_binds);
    if (num_args != num_binds) {
        set_eval_error("Wrong number of args ("+(string)num_args+")");
        return [];
    }
    return args;
}

integer do_apply(string s) {
    string n = llJsonGetValue(s,["n"]);
    list path = llJson2List(llJsonGetValue(s,["path"]));
    if (n == "start") {
        if (JSON_OBJECT != llJsonValueType(form,path+1)) {
            set_eval_error("Not a function: "+llJsonGetValue(form,path+1));
            return DONE;
        }
        list binds = llDeleteSubList(llJson2List(llJsonGetValue(form, path+[1, "binds"])), 0, 0);
        integer is_native = (JSON_INVALID != llJsonValueType(form,path+[1,"id"]));
        list args = validate_args(binds,path);
        if (eval_error) return DONE;
//        llOwnerSay("eval: apply args="+llList2Json(JSON_ARRAY,args));
        if (is_native) {
            integer native_id = (integer)llJsonGetValue(form,path+[1, "id"]);
            s=llJsonSetValue(s,["mode"],"native");
            update(llJsonSetValue(s,["n"],"after_native"));
            send_native_req("consume_args", native_id, args);
            return WAIT;
        } else {
            set_eval_error("Cannot evaluate closures");
            return DONE;
        }
    }
    if (n == "after_native") {
        if (msg_type != MSG_NATIVE_RESP) {
            set_eval_error("apply: unexpected message "+msg);
            return DONE;
        }
        string result = llJsonGetValue(msg,["data"]);
        if (JSON_FALSE == llJsonGetValue(msg,["success?"])) {
            set_eval_error(result);
            return DONE;
        }
        if (JSON_STRING == llJsonValueType(msg,["data"]))
            result=requote(result);
//        llOwnerSay("eval: apply result: "+result);
        form=llJsonSetValue(form,path,result);
        if (JSON_STRING == llJsonValueType(msg,["data"]) && path==[]) {
            form = requote(form);
        }
//        llOwnerSay("eval: form: "+form);
        pop();
        return GO;
    }
    set_eval_error("Unrecognized apply step: "+n);
    return DONE;    
}

// run results
integer WAIT = 0;
integer DONE = 1;
integer GO = 2;

integer run() {
    integer status = GO;
    while (!is_empty() && status == GO) {
        string step = peek();
        integer step_code = (integer)llJsonGetValue(step,["s"]);
//        llOwnerSay("step: "+step+" ("+(string)llGetFreeMemory()+")");
//        llOwnerSay("form: "+form);
        //dump_stack();
        if (step_code == EVAL) status = do_eval(step);
        else if (step_code == EVAL_AST) status = do_eval_ast(step);
        else if (step_code == APPLY)    status = do_apply(step);
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
            resp = json_obj(["tag", tag, "success?", JSON_FALSE, "data", eval_error_message]);
        } else {
            resp = json_obj(["tag", tag, "success?", JSON_TRUE]);
            resp = llJsonSetValue(resp,["data"],form);
        }
        llMessageLinked(LINK_THIS, MSG_EVAL_RESP, resp, me);
        return DONE;
    } else {
        //llOwnerSay("eval: waiting");
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
        llOwnerSay("eval: ready ("+(string)llGetFreeMemory()+")");
    }
     
    link_message(integer sender, integer num, string str, key id)
    {
        if (me == id) return;
        if (num == MSG_EVAL_REQ) {
            form = llJsonGetValue(str,["data"]);
            if (JSON_STRING == llJsonValueType(str,["data"]))
                form = requote(form);
            tag = llJsonGetValue(str,["tag"]);
            state evaluating;
        }
    }
}

state evaluating
{
    state_entry()
    {
        llOwnerSay("eval: evaluating");
        push(eval([],GLOBAL_ENV));
        if (DONE == continue()) {
            state default;
        }
    }
    
    link_message(integer sender, integer num, string str, key id) {
        if (me == id) return;
        msg_type = num;
        msg = str;
        if (DONE == continue()) {
            state default;
        }
    }
}
