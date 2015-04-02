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

string GLOBAL_ENV = "GLOBAL";

string json_obj(list parts) {
    return llList2Json(JSON_OBJECT, parts);
}

string json_array(list l) {
    return llList2Json(JSON_ARRAY, l);
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


////////// ENVIRONMENT ////////////////////
string env_map = "{}";

string get(string env_id, string k) {
    return llJsonGetValue(env_map, [env_id, k]);
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
    add_native_fn(FN_PRSTR, "pr-str", ["s"]);
    add_native_fn(FN_ADD, "+", ["&", "y"]);
    add_native_fn(FN_SUB, "-", ["&", "y"]);
    add_native_fn(FN_MUL, "*", ["&", "y"]);
    add_native_fn(FN_DIV, "/", ["&", "y"]);
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
        }
    }
}
