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
send_eval_resp(string tag, string success) {
    string resp = json_obj(["tag", tag, "success?", success]);
    if (success == JSON_TRUE) {
        resp = llJsonSetValue(resp,["data"],form);
    } else {
        resp = llJsonSetValue(resp,["data"],eval_error_message);
    }
    llMessageLinked(LINK_THIS, MSG_EVAL_RESP, resp, me);
}

// MSG_LOOKUP_REQ: {"tag": <string>, "env_id": <string>, "symbol":<string>}
integer MSG_LOOKUP_REQ = 4;
send_lookup(string env_id, string symbol, string tag) {
    string req = llList2Json(JSON_OBJECT, ["env_id", env_id, "symbol", symbol, "tag", "eval*_"+tag]);
    llMessageLinked(LINK_THIS, MSG_LOOKUP_REQ, req, me);
}

// MSG_LOOKUP_RESP: {"tag": <string>, "success?": <boolean>, "data":<string or form>}
integer MSG_LOOKUP_RESP = 5;

// MSG_NATIVE_REQ: {"tag":<string>, "native_id": <integer>, "args": <array>}
integer MSG_NATIVE_REQ = 6;

send_native_req(string tag, integer id, list args) {
    string r = json_obj(["tag", "eval*_"+tag, "native_id", id, "args", json_array(args)]);
    llMessageLinked(LINK_THIS, MSG_NATIVE_REQ, r, me);
}

// MSG_NATIVE_RESP: {"tag":<string>, "success?": <boolean>, "data": <form or string>}
integer MSG_NATIVE_RESP = 7;


// MSG_ENV_CREATE_REQ: {"tag": <string>, "outer_id": <string>, "binds": <list of names>, "args", <list of values>}
integer MSG_ENV_CREATE_REQ = 8;
send_env_create_req(string tag, string outer_id, list binds, list args) {
    string r = json_obj(["tag", "eval*_"+tag, "outer_id", outer_id,"binds", json_array(binds), "args", json_array(args)]);
    llMessageLinked(LINK_THIS, MSG_ENV_CREATE_REQ, r, me);
}

// MSG_ENV_CREATE_RESP: {"tag": <string>, "data": <string>}
integer MSG_ENV_CREATE_RESP = 9;

// MSG_ENV_SET_REQ: {"tag": <string>, "env_id": <string>, "symbol": <string>, "data": <form>}
integer MSG_ENV_SET_REQ = 12;
send_env_set_req(string tag, string env_id, string symbol, string form) {
    string r = json_obj(["tag", "eval*_"+tag, "env_id", env_id, "symbol", symbol]);
    r=llJsonSetValue(r,["data"],form);
    llMessageLinked(LINK_THIS, MSG_ENV_SET_REQ, r, me);
}

// MSG_ENV_SET_RESP: {"tag": <string>}
integer MSG_ENV_SET_RESP = 13;

// MSG_ENV_INCREF_REQ: {"tag": <string>, "env_id": <string>}
integer MSG_ENV_INCREF_REQ = 14;
send_env_incref_req(string tag, string env_id) {
    string r = json_obj(["tag", "eval*_"+tag, "env_id", env_id]);
    llMessageLinked(LINK_THIS, MSG_ENV_INCREF_REQ, r, me);
}

// MSG_ENV_INCREF_RESP: {"tag": <string>}
integer MSG_ENV_INCREF_RESP = 15;

// MSG_ENV_DECREF_REQ: {"tag": <string>, "env_id": <string>}
integer MSG_ENV_DECREF_REQ = 16;
send_env_decref_req(string tag, string env_id) {
    string r = json_obj(["tag", "eval*_"+tag, "env_id", env_id]);
    llMessageLinked(LINK_THIS, MSG_ENV_DECREF_REQ, r, me);
}

// MSG_ENV_DECREF_RESP: {"tag": <string>}
integer MSG_ENV_DECREF_RESP = 17;

// MSG_EVAL_LET_REQ: {"tag:":<string>,"data":<form>, "path": <list of strings>, "env_id": <string>}
integer MSG_EVAL_LET_REQ = 18;
send_eval_let_req(string tag, list path, string env_id) {
    string r = json_obj(["tag", "eval*_"+tag, "env_id", env_id, "path", json_array(path), "form", form]);
    llMessageLinked(LINK_THIS, MSG_EVAL_LET_REQ, r, me);
}

///////////// STEPS ////////////////

string json_obj(list parts) {
    return llList2Json(JSON_OBJECT, parts);
}

string json_array(list l) {
    return llList2Json(JSON_ARRAY, l);
}

integer decref_if_needed(list path) {
    llOwnerSay("eval: decref_if_needed: path=["+llDumpList2String(path, ",")+"]");
    // If the result was a function, then it has a ref on its closed-over environment,
    // and that ref isn't going to be released by function application, so we release it
    // to avoid leaking the closed over environment.
    if (JSON_OBJECT == llJsonValueType(form,path)) {
        send_env_decref_req("done", llJsonGetValue(form,path+["env_id"]));
        return WAIT;
    }
    return GO;
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
        string type = llJsonValueType(form,path);
        if (JSON_ARRAY == type) {
            integer _tag = (integer)llJsonGetValue(form,path+0);
            if (LIST == _tag) {
                if (JSON_ARRAY == llJsonValueType(form, path+1) &&
                    SYMBOL == (integer)llJsonGetValue(form, path+[1, 0])) {
                    string symbol = llJsonGetValue(form, path+[1, 1]);
                    if ("def!" == symbol) {
                        update(llJsonSetValue(s,["n"],"eval_end"));
                        push(def(path, env_id));
                        return GO;
                    } else if ("do" == symbol) {
                        update(llJsonSetValue(s,["n"],"eval_end"));
                        push(_do(path,env_id));
                        return GO;
                    } else if ("let*" == symbol) {
                        s = llJsonSetValue(s,["tag"],tag);
                        update(llJsonSetValue(s,["n"],"after_special"));
                        //push(let(path, env_id));
                        send_eval_let_req("eval_after_let",path,env_id);
                        return WAIT;
                    } else if ("fn*" == symbol) {
                        update(llJsonSetValue(s,["n"],"eval_end"));
                        push(fn(path, env_id));
                        return GO;
                    } else if ("if" == symbol) {
                        update(llJsonSetValue(s,["n"],"eval_end"));
                        push(_if(path, env_id));
                        return GO;
                    }
                }
                s=llJsonSetValue(s,["apply"],JSON_TRUE);
            }
        }
        
        update(llJsonSetValue(s,["n"], "after_ast"));
        push(eval_ast(path, env_id));
        return GO;
    }
    if (n == "after_ast") {
        update(llJsonSetValue(s,["n"],"eval_end"));
        string type = llJsonValueType(form,path);
        if (JSON_TRUE == llJsonGetValue(s,["apply"])) {
            push(apply(path));
        }
        return GO;
    }
    if (n == "after_special") {
        tag = llJsonGetValue(s,["tag"]);
        if (JSON_FALSE == llJsonGetValue(msg,["success?"])) {
            set_eval_error(llJsonGetValue(msg,["data"]));
            return DONE;
        }
        form = llJsonGetValue(msg,["data"]);
        if (JSON_STRING == llJsonValueType(msg,["data"]))
            form = requote(form);
        n = "eval_end";
    }
    if (n == "eval_end") {
        pop();
        if (JSON_TRUE == llJsonGetValue(s,["respond"])) {
            return DONE;
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
            } else if (KEYWORD == tag) {
                pop();
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
            // if we just copied a closure, we need to up the refcount to the referenced environment
            if (JSON_OBJECT == llJsonValueType(data,[]) && JSON_INVALID == llJsonValueType(data,["id"])) {
                string id = llJsonGetValue(data,["env_id"]);
                send_env_incref_req("eval_ast",id);
                return WAIT;
            } else {
                return GO;
            }
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
//    llOwnerSay("eval: validate_args: num_args="+(string)num_args+" num_binds="+(string)num_binds);
//    llOwnerSay("eval: validate_args: "+llJsonGetValue(form,path));
    if ("[1,\"&\"]" == llList2String(binds,num_binds-2)) {
//        llOwnerSay("eval: validate_args: varargs!");
        if (num_args < num_binds - 2) {
            set_eval_error("Not enough args (needed "+(string)(num_binds-2)+")");
            return [];
        }
        if (num_args > num_binds - 2) {
            string last_arg = llList2Json(JSON_ARRAY,[LIST]+llList2List(args,num_binds-2,num_args-1));
            args = llListReplaceList(args,[last_arg],num_binds-2,num_args-1);
        } else {
            args = args + "[]";
        }
    } else {
        if (num_args != num_binds) {
            set_eval_error("Wrong number of args ("+(string)num_args+")");
            return [];
        }
    }
//    llOwnerSay("eval: validate_args: args="+llDumpList2String(args,","));
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
            update(llJsonSetValue(s,["n"],"consume_args"));
            send_native_req("consume_args", native_id, args);
            return WAIT;
        } else {
            string closure_env_id = llJsonGetValue(form,path+[1,"env_id"]);
            s=llJsonSetValue(s,["n"],"consume_args");
            s=llJsonSetValue(s,["closure_env_id"],closure_env_id);
            s=llJsonSetValue(s,["mode"],"closure");
            update(s);
            send_env_create_req("consume_args", closure_env_id, binds, args);
            return WAIT;
        }
    }
    if (n == "consume_args") {
        // we're 'consuming' each argument, so any arguments that are functions need to have their
        // closed-over environments decref'd
        integer i = (integer)llJsonGetValue(s,["i"]);
        if (i==2) {
            string new_env_id = llJsonGetValue(msg,["data"]);
            s=llJsonSetValue(s,["new_env_id"],new_env_id);
        }
        if (JSON_INVALID == llJsonValueType(form,path+i)) {
            if ("closure"==llJsonGetValue(s,["mode"])) {
                update(llJsonSetValue(s,["n"],"after_env_create"));
            } else {
                update(llJsonSetValue(s,["n"],"after_native"));
            }
            return GO;
        } else {
            update(llJsonSetValue(s,["i"],(string)(i+1)));
            if (JSON_OBJECT == llJsonValueType(form,path+i) && JSON_INVALID == llJsonValueType(form,path+[i,"id"])) {
                send_env_decref_req("consume_args", llJsonGetValue(form,path+[i,"env_id"]));
                return WAIT;
            }
            return GO;
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
    if (n == "after_env_create") {
        string body = llJsonGetValue(form,path+[1,"body"]);
        if (JSON_STRING == llJsonValueType(form,path+[1,"body"]))
            body = requote(body);
        s=llJsonSetValue(s,["n"],"after_eval");
        update(s);
        if (path == []) form = body;
        else form=llJsonSetValue(form,path,body);
        string new_env_id = llJsonGetValue(s,["new_env_id"]);
        push(eval(path,new_env_id));
        return GO;
    }
    if (n == "after_eval") {
        string new_env_id = llJsonGetValue(s,["new_env_id"]);
        update(llJsonSetValue(s,["n"],"after_decref"));
        send_env_decref_req("after_delete_env",new_env_id);
        return WAIT;
    }
    if (n == "after_decref") {
        string closure_env_id = llJsonGetValue(s,["closure_env_id"]);
        pop();
        send_env_decref_req("after_decref", closure_env_id);
        return WAIT;
    }
    set_eval_error("Unrecognized apply step: "+n);
    return DONE;    
}

integer DEF = 3;
string def(list path, string env_id) {
    return json_obj(["s",    (string)DEF,
                     "n",    "start",
                     "path", json_array(path),
                     "env_id", env_id]);
}

integer do_def(string s) {
    string n = llJsonGetValue(s,["n"]);
    list path = llJson2List(llJsonGetValue(s,["path"]));
    string env_id = llJsonGetValue(s,["env_id"]);
    if (n == "start") {
        string json_sym = llJsonGetValue(form, path+2);
        string json_val = llJsonGetValue(form, path+3);
        if (JSON_INVALID == json_sym || JSON_INVALID == json_val) {
            set_eval_error("def! requires two args");
            return DONE;
        }
        if (JSON_ARRAY != llJsonValueType(json_sym, []) || SYMBOL !=(integer) llJsonGetValue(json_sym, [0])) {
            set_eval_error("First arg to def! must be a symbol");
            return DONE;
        }
        string k = llJsonGetValue(json_sym, [1]);
        s = llJsonSetValue(s,["n"],"after_eval");
        s = llJsonSetValue(s,["symbol"],k);
        update(s);
        push(eval(path+3,env_id));
        return GO;
    }
    if (n == "after_eval") {
        string symbol = llJsonGetValue(s,["symbol"]);
        string result = llJsonGetValue(form,path+3);
        if (JSON_STRING == llJsonValueType(form,path+3))
            result = requote(result);
        form=llJsonSetValue(form,path,result);
        update(llJsonSetValue(s,["n"],"after_set"));
        send_env_set_req("after_set",env_id,symbol,result);
        return WAIT;
    }
    if (n == "after_set") {
        pop();
        return GO;
    }
    set_eval_error("Unrecognized def step: "+n);
    return DONE;    
}

integer DO = 4;
string _do(list path, string env_id) {
    return json_obj(["s",    (string)DO,
                     "n",    "children",
                     "i",    2,
                     "path", json_array(path),
                     "env_id", env_id]);
}

integer do_do(string s) {
    string n = llJsonGetValue(s,["n"]);
    list path = llJson2List(llJsonGetValue(s,["path"]));
    string env_id = llJsonGetValue(s,["env_id"]);
    integer i = (integer)llJsonGetValue(s,["i"]);
    if (n == "children") {
        integer i = (integer)llJsonGetValue(s,["i"]);
        if (JSON_INVALID == llJsonValueType(form,path+i)) {
            string result;
            if (i == 2) {
                result = JSON_NULL;
            } else {
                result = llJsonGetValue(form,path+(i-1));
                if (JSON_STRING == llJsonValueType(form,path+(i-1)))
                    result = requote(result);
            }
            form = llJsonSetValue(form,path,result);
            pop();
            return GO;
        } else {
            if (i == 2) {
                update(llJsonSetValue(s,["i"],(string)(i+1)));
                push(eval(path+i,env_id));
                return GO;
            } else {
                update(llJsonSetValue(s,["n"], "after_decref"));
                return decref_if_needed(path+(i-1));
            }
        }
    }
    if (n == "after_decref") {
        s=llJsonSetValue(s,["i"],(string)(i+1));
        update(llJsonSetValue(s,["n"],"children"));
        push(eval(path+i,env_id));
        return GO;
    }
    set_eval_error("Unrecognized do step: "+n);
    return DONE;    
}

integer FN = 6;
string fn(list path, string env_id) {
    return json_obj(["s", FN,
                     "n", "start",
                     "path", json_array(path),
                     "env_id", env_id]);
}

integer do_fn(string s) {
    list path = llJson2List(llJsonGetValue(s,["path"]));
    string env_id = llJsonGetValue(s,["env_id"]);
    string closure = "{}";
    string binds = llJsonGetValue(form, path+2);
    string body = llJsonGetValue(form, path+3);
    if (JSON_INVALID == binds || JSON_INVALID == body) {
        set_eval_error("fn* requires 2 args");
        return GO;
    }
    if (JSON_STRING == llJsonValueType(form,path+3))
        body = requote(body);
    closure = llJsonSetValue(closure, ["binds"], binds);
    closure = llJsonSetValue(closure, ["env_id"], env_id);
    closure = llJsonSetValue(closure, ["body"], body);
    pop();
    form=llJsonSetValue(form,path,closure);
    send_env_incref_req("do_fn", env_id);
    return WAIT;
}

integer IF = 7;
string _if(list path, string env_id) {
    return json_obj(["s", IF,
                     "n", "start",
                     "path", json_array(path),
                     "env_id", env_id]);
}

integer do_if(string s) {
    string n = llJsonGetValue(s,["n"]);
    list path = llJson2List(llJsonGetValue(s,["path"]));
    string env_id = llJsonGetValue(s,["env_id"]);
    if (n == "start") {
        update(llJsonSetValue(s,["n"],"after_condition"));
        push(eval(path+2, env_id));
        return GO;
    }
    if (n == "after_condition") {
        string cond = llJsonValueType(form,path+2);
        if (JSON_FALSE == cond || JSON_NULL == cond) {
            if (JSON_INVALID == llJsonValueType(form,path+4)) {
                form = llJsonSetValue(form,path,JSON_NULL);
                pop();
                return GO;
            } else {
                form = llJsonSetValue(form,path,read_form(path+4));
                pop();
                push(eval(path,env_id));
                return GO;
            }
        } else {
            form = llJsonSetValue(form,path,read_form(path+3));
            pop();
            push(eval(path,env_id));
            return GO;
        }
    }
    set_eval_error("Unrecognized if step: "+n);
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
        else if (step_code == DEF)      status = do_def(step);
        else if (step_code == DO)       status = do_do(step);
//        else if (step_code == LET)      status = do_let(step);
        else if (step_code == FN)       status = do_fn(step);
        else if (step_code == IF)       status = do_if(step);
        else {
            set_eval_error("invalid step code: "+(string)step_code);
            status = DONE;
        }
        //dump_stack();
    }
    if (is_empty()) {
        decref_if_needed([]);
        return DONE;
    } else {
        return status;
    }
}

integer continue() {
    if (DONE == run()) {
        string resp;
        if (eval_error) {
//            llOwnerSay("eval: failed: "+eval_error_message);
            send_eval_resp(tag, JSON_FALSE);
            eval_error = FALSE;
            eval_error_message = "";
            integer done;
            do {
                string s = peek();
//                llOwnerSay("eval: popping after error: "+s);
                done = s == "" || llJsonGetValue(s,["respond"]) == JSON_TRUE;
                pop();
            } while (!done);
        } else {
            send_eval_resp(tag, JSON_TRUE);
        }
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
//        llOwnerSay("eval: msg: "+str);
        string _tag = llJsonGetValue(str,["tag"]);
        if (num == MSG_EVAL_REQ) {
            form = llJsonGetValue(str,["data"]);
            if (JSON_STRING == llJsonValueType(str,["data"]))
                form = requote(form);
            tag = _tag;
            if (JSON_INVALID != llJsonValueType(str,["path"])) {
                list path = llJson2List(llJsonGetValue(str,["path"]));
                string env_id = llJsonGetValue(str,["env_id"]);
                push(eval(path,env_id));
            } else {
                push(eval([],GLOBAL_ENV));
            }
            update(llJsonSetValue(peek(), ["respond"],JSON_TRUE));
            continue();
        } else if ("eval*_" == llGetSubString(_tag,0,5)&&!is_empty()) {
            msg_type = num;
            msg = str;
            continue();
        }
    }
}

