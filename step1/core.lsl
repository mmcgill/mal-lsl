key me = NULL_KEY;

// tags for forms
integer LIST = 0;
integer SYMBOL = 1;
integer KEYWORD = 2;
integer VECTOR = 3;
integer HASHMAP = 5;
// any tag > NATIVE represents a native fn
integer NATIVE_FN = 100;
integer FN_PRSTR = 105;

// for keywords as map keys
string KEYWORD_PREFIX = "ʞ";

string escape_str(string s) {
    list parts = llParseString2List(s,[],["\\","\""]);
    integer i;
    s = "";
    for (i=0; i < llGetListLength(parts); i++) {
        string part = llList2String(parts,i);
        if (part == "\\") s += "\\\\";
        else if (part == "\"") s += "\\\"";
        else s += part;
    }
    return s;
}

string requote(string s) {
    return "\""+escape_str(s)+"\"";
}

string read_form(string s, list path) {
    if (JSON_STRING == llJsonValueType(s,path))
        return requote(llJsonGetValue(s,path));
    else
        return llJsonGetValue(s,path);
}

//////////// MESSAGES ///////////////////

string json_obj(list parts) {
    return llList2Json(JSON_OBJECT, parts);
}

string json_array(list l) {
    return llList2Json(JSON_ARRAY, l);
}

// MSG_NATIVE_REQ: {"tag":<string>, "native_id": <integer>, "args": <array>}
integer MSG_NATIVE_REQ = 6;

// MSG_NATIVE_RESP: {"tag":<string>, "success?": <boolean>, "data": <form or string>}
integer MSG_NATIVE_RESP = 7;

send_native_resp(string tag, string success, string data) {
    string r = json_obj(["tag", tag, "success?", success]);
    r = llJsonSetValue(r,["data"],data);
    llMessageLinked(LINK_THIS, MSG_NATIVE_RESP, r, me);
}

////////////// FUNCTIONS ////////////////////

list args;
string args_str;
string core_error_message;
string error(string msg) {
    core_error_message = msg;
    return JSON_INVALID;
}

string form;
integer pr_str_error;
string pr_str_error_message;
string _pr_str(list path) {
    string type = llJsonValueType(form, path);
    if (JSON_OBJECT == type) {
        return "#<function>";
    } else if (JSON_TRUE == type) {
        return "true";
    } else if (JSON_FALSE == type) {
        return "false";
    } else if (JSON_NUMBER == type) {
        return llJsonGetValue(form,path);
    } else if (JSON_NULL == type) {
        return "nil";
    } else if (JSON_STRING == type) {
        return escape_str(requote(llJsonGetValue(form, path)));
    } else if (JSON_ARRAY == type) {
        integer t = (integer)llJsonGetValue(form, path+0);
//        llOwnerSay("pr_str: type "+(string)t);
        if (LIST == t || VECTOR == t) {
            string s;
            integer i = 1;
            if (LIST == t) s = "("; else s = "[";
            while (JSON_INVALID != llJsonValueType(form,path+i)) {
                if (llStringLength(s) > 1) s += " ";
                s = s + _pr_str(path+i);
                i = i + 1;
                if (pr_str_error) return "";
            }
            if (LIST == t) s += ")"; else s += "]";
            return s;
        } else if (SYMBOL == t || KEYWORD == t) {
            return llJsonGetValue(form,path+1);
        } else if (HASHMAP == t) {
            integer i;
            string s;
            list forms = llJson2List(llJsonGetValue(form,path+1));
//            llOwnerSay("pr_str: forms="+llDumpList2String(forms," "));
            for (i=0; i<llGetListLength(forms); i+=2) {
                if (i > 0) s = s + " ";
                string k = llList2String(forms,i);
                string kstr;
                if (KEYWORD_PREFIX == llGetSubString(k,0,0)) {
                    kstr = llGetSubString(k,1,-1);
                } else {
                    kstr = escape_str(requote(k));
                }
                s = s + kstr +" " + _pr_str(path+[1,k]);
            }
            return "{"+s+"}";
        } else {
            pr_str_error = 1;
            pr_str_error_message = "<ERROR> unknown tag " + (string)t;
            return "";
        }
    } else {
        pr_str_error = 1;
        pr_str_error_message = "pr_str: CANNOT PRINT " + form;
        return "";
    }
}

string pr_str() {
    form = llJsonGetValue(args_str, [0]);
    if (JSON_STRING == llJsonValueType(args_str,[0]))
        form = requote(form);
//    llOwnerSay("core: pr_str("+form+")");
    args = [];
    args_str = "";
    pr_str_error = 0;
    pr_str_error_message = "";
    string result = "\""+_pr_str([])+"\"";
    if (pr_str_error) {
        return error(pr_str_error_message);
    } else {
//        llOwnerSay("core: pr_str="+result);
        return result;
    }
}

string run(integer id) {
    if (FN_PRSTR == id) return pr_str();
    return error("Unrecognized native fn id: "+(string)id);
}

free() {
    form = "";
    args = [];
    args_str = "";
    pr_str_error = 0;
    pr_str_error_message = "";
    core_error_message = "";
}

default
{
    state_entry()
    {
        if (me == NULL_KEY) me = llGenerateKey();
        llOwnerSay("core: ready ("+(string)llGetFreeMemory()+")");
    }
    
    link_message(integer sender, integer num, string str, key id)
    {
        if (me == id) return;
        if (num == MSG_NATIVE_REQ) {
            core_error_message = "";
            string tag = llJsonGetValue(str,["tag"]);
            integer id = (integer)llJsonGetValue(str,["native_id"]);
            args_str = llJsonGetValue(str,["args"]);
            args = llJson2List(args_str);
//            llOwnerSay("core: args="+args_str);
            string data = run(id);
            if (JSON_INVALID == data) {
                send_native_resp(tag, JSON_FALSE, core_error_message);
            } else {
                send_native_resp(tag, JSON_TRUE, data);
            }
            free();
//            llOwnerSay("core: ready ("+(string)llGetFreeMemory()+")");
        }
    }
}
