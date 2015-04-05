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
    string r = json_obj(["tag", tag, "success?", success, "data", data]);
    llMessageLinked(LINK_THIS, MSG_LOOKUP_RESP, r, me);
}

// MSG_ENV_CREATE_REQ: {"tag": <string>, "outer_id": <string>}
integer MSG_ENV_CREATE_REQ = 8;

// MSG_ENV_CREATE_RESP: {"tag": <string>, "data": <string>}
integer MSG_ENV_CREATE_RESP = 9;
send_env_create_resp(string tag,string env_id) {
    string r = json_obj(["tag", tag, "data", env_id]);
    llMessageLinked(LINK_THIS, MSG_ENV_CREATE_RESP, r, me);
}

// MSG_ENV_DELETE_REQ: {"tag": <string>, "env_id": <string>}
integer MSG_ENV_DELETE_REQ = 10;

// MSG_ENV_DELETE_RESP: {"tag": <string>}
integer MSG_ENV_DELETE_RESP = 11;
send_env_delete_resp(string tag) {
    string r = json_obj(["tag", tag]);
    llMessageLinked(LINK_THIS, MSG_ENV_DELETE_RESP, r, me);
}

// MSG_ENV_SET_REQ: {"tag": <string>, "env_id": <string>, "symbol": <string>, "data": <form>}
integer MSG_ENV_SET_REQ = 12;

// MSG_ENV_SET_RESP: {"tag": <string>}
integer MSG_ENV_SET_RESP = 13;
send_env_set_resp(string tag) {
    string r = json_obj(["tag", tag]);
    llMessageLinked(LINK_THIS, MSG_ENV_SET_RESP, r, me);
}

////////// ENVIRONMENT ////////////////////
string env_map = "{}";
string env_outer_map = "{}";
integer next_env_id = 0;

string create(string outer_id) {
    string env_id = (string)next_env_id;
    next_env_id += 1;
    env_map = llJsonSetValue(env_map, [env_id], "{}");
    if ("" != outer_id) {
        env_outer_map = llJsonSetValue(env_outer_map, [env_id], outer_id);
    }
    return env_id;
}

delete(string env_id) {
    if (GLOBAL_ENV == env_id) {
        llOwnerSay("env: WARNING: tried to delete global env");
        return;
    }
    env_map = llJsonSetValue(env_map, [env_id], JSON_DELETE);
    env_outer_map = llJsonSetValue(env_outer_map, [env_id], JSON_DELETE);
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
//            llOwnerSay("env_find: base case");
            return "";
        } else {
//            llOwnerSay("env_find: checking outer ("+env_id+" "+k+")");
            return find(outer_id, k);
        }
    } else {
//        llOwnerSay("env_find: found ("+env_id+" "+k+")");
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
            string env_id = create(outer_id);
            send_env_create_resp(tag, env_id);
        } else if (num == MSG_ENV_DELETE_REQ) {
            string tag = llJsonGetValue(str,["tag"]);
            string env_id = llJsonGetValue(str,["env_id"]);
            delete(env_id);
            send_env_delete_resp(tag);
        } else if (num == MSG_ENV_SET_REQ) {
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
        }
    }
}
