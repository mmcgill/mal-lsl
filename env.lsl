key me = NULL_KEY;

// tags for forms
integer LIST = 0;
integer SYMBOL = 1;
integer KEYWORD = 2;
integer VECTOR = 3;
// any tag > NATIVE represents a native fn
integer NATIVE_FN = 100;
integer FN_ADD = 101;
integer FN_SUB = 102;
integer FN_MUL = 103;
integer FN_DIV = 104;
integer FN_PRSTR = 105;
integer FN_LIST_QMARK = 106;
integer FN_EMPTY_QMARK = 107;
integer FN_COUNT = 108;
integer FN_LESS_THAN = 110;

string GLOBAL_ENV = "GLOBAL";

string json_obj(list parts) {
    return llList2Json(JSON_OBJECT, parts);
}

string json_array(list l) {
    return llList2Json(JSON_ARRAY, l);
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

////////// MESSAGES ////////////////////

// MSG_LOOKUP_REQ: {"tag": <string>, "env_id": <string>, "symbol":<string>}
integer MSG_LOOKUP_REQ = 4;

// MSG_LOOKUP_RESP: {"tag": <string>, "success?": <boolean>, "data":<string or form>}
integer MSG_LOOKUP_RESP = 5;
send_lookup_resp(string tag, string success, string data) {
    string r = json_obj(["tag", tag, "success?", success]);
    r=llJsonSetValue(r,["data"],data);
    llMessageLinked(LINK_THIS, MSG_LOOKUP_RESP, r, me);
}

// MSG_ENV_CREATE_REQ: {"tag": <string>, "outer_id": <string>, "binds": <list of names>, "args", <list of forms>}
integer MSG_ENV_CREATE_REQ = 8;

// MSG_ENV_CREATE_RESP: {"tag": <string>, "data": <string>}
integer MSG_ENV_CREATE_RESP = 9;
send_env_create_resp(string tag,string env_id) {
    string r = json_obj(["tag", tag, "data", env_id]);
    llMessageLinked(LINK_THIS, MSG_ENV_CREATE_RESP, r, me);
}

// MSG_ENV_SET_REQ: {"tag": <string>, "env_id": <string>, "symbol": <string>, "data": <form>}
integer MSG_ENV_SET_REQ = 12;

// MSG_ENV_SET_RESP: {"tag": <string>}
integer MSG_ENV_SET_RESP = 13;
send_env_set_resp(string tag) {
    string r = json_obj(["tag", tag]);
    llMessageLinked(LINK_THIS, MSG_ENV_SET_RESP, r, me);
}

// MSG_ENV_INCREF_REQ: {"tag": <string>, "env_id": <string>}
integer MSG_ENV_INCREF_REQ = 14;

// MSG_ENV_INCREF_RESP: {"tag": <string>}
integer MSG_ENV_INCREF_RESP = 15;
send_env_incref_resp(string tag) {
    string r = json_obj(["tag", tag]);
    llMessageLinked(LINK_THIS, MSG_ENV_INCREF_RESP, r, me);
}

// MSG_ENV_DECREF_REQ: {"tag": <string>, "env_id": <string>}
integer MSG_ENV_DECREF_REQ = 16;

// MSG_ENV_DECREF_RESP: {"tag": <string>}
integer MSG_ENV_DECREF_RESP = 17;
send_env_decref_resp(string tag) {
    string r = json_obj(["tag", tag]);
    llMessageLinked(LINK_THIS, MSG_ENV_DECREF_RESP, r, me);
}

////////// ENVIRONMENT ////////////////////
string env_map = "{}";
string env_outer_map = "{}";
string env_refcounts = "{}";
integer next_env_id = 0;

string create(string outer_id, string binds, string args) {
    string env_id = (string)next_env_id;
    next_env_id += 1;
    env_map = llJsonSetValue(env_map, [env_id], "{}");
    if ("" != outer_id) {
        env_outer_map = llJsonSetValue(env_outer_map, [env_id], outer_id);
    }
    env_refcounts = llJsonSetValue(env_refcounts, [env_id], "1");
    llOwnerSay("env: create: binds="+binds+" args="+args);
    integer i = 0;
    while (JSON_INVALID != llJsonValueType(args,[i])) {
        string k = llJsonGetValue(binds,[i,1]);
        string v = llJsonGetValue(args,[i]);
        if (JSON_STRING == llJsonValueType(args,[i]))
            v = requote(v);
        llOwnerSay("env: create: "+k+"="+v);
        set(env_id,k,v);
        i++;
    }
    return env_id;
}

delete(string env_id) {
    if (GLOBAL_ENV == env_id) {
        llOwnerSay("env: WARNING: tried to delete global env");
        return;
    }
    llOwnerSay("env: deleting "+env_id);
    
    env_map = llJsonSetValue(env_map, [env_id], JSON_DELETE);
    env_outer_map = llJsonSetValue(env_outer_map, [env_id], JSON_DELETE);
    env_refcounts = llJsonSetValue(env_refcounts, [env_id], JSON_DELETE);
}

// return the id of the outer environment
string env_outer(string env_id) {
    string outer_id = llJsonGetValue(env_outer_map, [env_id]);
    if (JSON_INVALID == outer_id) {
        return "";
    } else {
        return outer_id;
    }
}
// return the id of the environment that has k, or ""
string find(string env_id, string k) {
    if (JSON_INVALID == llJsonValueType(env_map, [env_id, k])) {
        string outer_id = env_outer(env_id);
        if ("" == outer_id) {
            return "";
        } else {
            return find(outer_id, k);
        }
    } else {
        return env_id;
    }
}

string get(string env_id, string k) {
//    llOwnerSay("env_get: "+env_map);
    env_id = find(env_id, k);
    if ("" == env_id) {
        return JSON_INVALID;
    } else {
        return llJsonGetValue(env_map, [env_id, k]);
    }
}

set(string env_id, string k, string v) {
    env_map = llJsonSetValue(env_map, [env_id, k], v);
}

inc_refcount(string env_id) {
    if (env_id != GLOBAL_ENV) {
        llOwnerSay("env: inc_refcount "+env_id);
        integer c = (integer)llJsonGetValue(env_refcounts, [env_id]);
        env_refcounts = llJsonSetValue(env_refcounts, [env_id], (string)(c+1));
    }
}

dec_refcount(string env_id) {
    if (env_id != GLOBAL_ENV) {
        llOwnerSay("env: dec_refcount "+env_id);
        integer c = (integer)llJsonGetValue(env_refcounts, [env_id]);
        env_refcounts = llJsonSetValue(env_refcounts, [env_id], (string)(c-1));
        if (c == 1) {
            delete(env_id);
        }
    }
}

add_native_fn(integer id, string name, list binds) {
    integer i = 0;
    for (i=0; i < llGetListLength(binds); i++) {
        binds = llListReplaceList(binds, [llList2Json(JSON_ARRAY, [SYMBOL, llList2String(binds,i)])], i, i);
    }
    string fn = json_obj(["id", id, "binds", llList2Json(JSON_ARRAY,[LIST]+binds), "env_id", GLOBAL_ENV]);
    set(GLOBAL_ENV, name, fn);
}

init_global_env() {
    env_map = json_obj([GLOBAL_ENV, "{}"]);
    add_native_fn(FN_PRSTR, "pr-str", ["s"]);
    add_native_fn(FN_ADD, "+", ["&", "y"]);
    add_native_fn(FN_SUB, "-", ["&", "y"]);
    add_native_fn(FN_MUL, "*", ["&", "y"]);
    add_native_fn(FN_DIV, "/", ["&", "y"]);
    add_native_fn(FN_EMPTY_QMARK, "empty?", ["x"]);
    add_native_fn(FN_LIST_QMARK, "list?", ["x"]);
    add_native_fn(FN_COUNT, "count", ["x"]);
    add_native_fn(FN_LESS_THAN, "<", ["x", "y"]);
}

default
{
    state_entry()
    {
        if (me == NULL_KEY) me = llGenerateKey();
        init_global_env();
        llOwnerSay("env: ready");
    }
    
    touch_start(integer num)
    {
        string s = "environments: ";
        list l = llJson2List(env_map);
        integer i;
        for (i=0; i < llGetListLength(l); i+=2) {
            if (i > 0) s += "; ";
            string k = llList2String(l,i);
            s += k+" ("+llJsonGetValue(env_refcounts, [k])+")";
        }
        llOwnerSay(s);
    }
    
    link_message(integer sender, integer num, string str, key id) {
        if (id == me) return;
        if (num == MSG_LOOKUP_REQ) {
            string tag = llJsonGetValue(str,["tag"]);
            string env_id = llJsonGetValue(str,["env_id"]);
            string symbol = llJsonGetValue(str,["symbol"]);
            string v = get(env_id, symbol);
            if (JSON_INVALID == v) {
                send_lookup_resp(tag, JSON_FALSE, "Undefined symbol "+symbol);
            } else {
                send_lookup_resp(tag, JSON_TRUE, v);
            }
        } else if (num == MSG_ENV_CREATE_REQ) {
            string tag = llJsonGetValue(str,["tag"]);
            string outer_id = llJsonGetValue(str,["outer_id"]);
            string env_id = create(outer_id,llJsonGetValue(str,["binds"]),llJsonGetValue(str,["args"]));
            send_env_create_resp(tag, env_id);
        } else if (num == MSG_ENV_SET_REQ) {
            llOwnerSay("env: set: msg="+str);
            string tag = llJsonGetValue(str,["tag"]);
            string env_id = llJsonGetValue(str,["env_id"]);
            string symbol = llJsonGetValue(str,["symbol"]);
            string v = llJsonGetValue(str,["data"]);
            if (JSON_STRING == llJsonValueType(str,["data"]))
                v = requote(v);
            set(env_id, symbol, v);
            llOwnerSay("env: set k="+symbol+" v="+v);
            llOwnerSay("env: "+env_map);
            send_env_set_resp(tag);
        } else if (num == MSG_ENV_INCREF_REQ) {
            string tag = llJsonGetValue(str,["tag"]);
            string env_id = llJsonGetValue(str,["env_id"]);
            inc_refcount(env_id);
            send_env_incref_resp(tag);
        } else if (num == MSG_ENV_DECREF_REQ) {
            string tag = llJsonGetValue(str,["tag"]);
            string env_id = llJsonGetValue(str,["env_id"]);
            dec_refcount(env_id);
            send_env_decref_resp(tag);
        }
    }
}
