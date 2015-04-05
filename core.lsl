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
        return "null";
    } else if (JSON_STRING == type) {
        // TODO: escape double quotes and backslashes
//        return "\\\"" + llJsonGetValue(form, path) + "\\\"";
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
    llOwnerSay("core: pr_str("+form+")");
    args = [];
    args_str = "";
    pr_str_error = 0;
    pr_str_error_message = "";
    string result = "\""+_pr_str([])+"\"";
    if (pr_str_error) {
        return error(pr_str_error_message);
    } else {
        llOwnerSay("core: pr_str="+result);
        return result;
    }
}

string add() {
    float result = llList2Float(args,0);
    integer i;
    for (i=1; i < llGetListLength(args); i++) {
        result += llList2Float(args,1);
    }
    return (string)result;
}

string subtract() {
    float result = llList2Float(args,0);
    integer i;
    for (i=1; i < llGetListLength(args); i++) {
        result -= llList2Float(args,1);
    }
    return (string)result;
}

string multiply() {
    float result = llList2Float(args,0);
    integer i;
    for (i=1; i < llGetListLength(args); i++) {
        result *= llList2Float(args,1);
    }
    return (string)result;
}

string divide() {
    float result = llList2Float(args,0);
    integer i;
    for (i=1; i < llGetListLength(args); i++) {
        result /= llList2Float(args,1);
    }
    return (string)result;
}

string list_qmark() {
    if (JSON_ARRAY == llJsonValueType(args_str, [0]) && LIST == (integer)llJsonGetValue(args_str, [0, 0])) {
        return JSON_TRUE;
    } else {
        return JSON_FALSE;
    }
}

string empty_qmark() {
    integer tag = (integer)llJsonGetValue(args_str, [0, 0]);
    if (JSON_ARRAY == llJsonValueType(args_str, [0]) && (LIST == tag || VECTOR == tag)) {
        if (1 < llGetListLength(llJson2List(llList2String(args,0)))) {
            return JSON_FALSE;
        } else {
            return JSON_TRUE;
        }
    } else {
        return error("Invalid type");
    }
}

string count() {
    integer tag = (integer)llJsonGetValue(args_str, [0, 0]);
    if (JSON_ARRAY == llJsonValueType(args_str, [0]) && (LIST == tag || VECTOR == tag)) {
        return (string)(llGetListLength(llJson2List(llList2String(args,0)))-1);
    } else {
        return error("Invalid type");
    }
}
/*
string equal(list args) {
    string x = llList2String(args,0);
    string y = llList2String(args,1);
    if (JSON_ARRAY == llJsonValueType(x, []) && JSON_ARRAY == llJsonValueType(y,[])) {
        integer xtag = (integer)llJsonGetValue(x,[0]);
        integer ytag = (integer)llJsonGetValue(y,[0]);
        if ((xtag == LIST || xtag == VECTOR) && (ytag == LIST || ytag == VECTOR)) {
            list xl = llJson2List(x);
            list yl = llJson2List(y);
            integer len = llGetListLength(xl);
            if (len != llGetListLength(yl)) {
                return JSON_FALSE;
            }
            integer i;
            for (i=1; i<len; i++) {
                if (JSON_TRUE != equal([llList2String(xl,i), llList2String(yl,i)]))
                    return JSON_FALSE;
            }
            return JSON_TRUE;
        } else if (xtag != ytag) {
            return JSON_FALSE;
        } else if (llJsonGetValue(x,[1]) == llJsonGetValue(y,[1])) {
            return JSON_TRUE;
        } else {
            return JSON_FALSE;
        }
    } else {
        if (x == y) return JSON_TRUE;
        else return JSON_FALSE;
    }
}

string less_than(list args) {
    if (JSON_NUMBER != llJsonValueType(llList2String(args,0), [])
    ||  JSON_NUMBER != llJsonValueType(llList2String(args,1), [])) {
        return set_eval_error("Invalid type");
    }
    float x = (float)llList2Float(args,0);
    float y = (float)llList2Float(args,1);
    if (x < y) return JSON_TRUE;
    return JSON_FALSE;
}

string less_than_equal(list args) {
    if (JSON_NUMBER != llJsonValueType(llList2String(args,0), [])
    ||  JSON_NUMBER != llJsonValueType(llList2String(args,1), [])) {
        return set_eval_error("Invalid type");
    }
    float x = (float)llList2Float(args,0);
    float y = (float)llList2Float(args,1);
    if (x <= y) return JSON_TRUE;
    return JSON_FALSE;
}

string greater_than(list args) {
    if (JSON_NUMBER != llJsonValueType(llList2String(args,0), [])
    ||  JSON_NUMBER != llJsonValueType(llList2String(args,1), [])) {
        return set_eval_error("Invalid type");
    }
    float x = (float)llList2Float(args,0);
    float y = (float)llList2Float(args,1);
    llOwnerSay("  "+(string)x+" > "+(string)y);
    if (x > y) return JSON_TRUE;;
    return JSON_FALSE;
}

string greater_than_equal(list args) {
    if (JSON_NUMBER != llJsonValueType(llList2String(args,0), [])
    ||  JSON_NUMBER != llJsonValueType(llList2String(args,1), [])) {
        return set_eval_error("Invalid type");
    }
    float x = (float)llList2Float(args,0);
    float y = (float)llList2Float(args,1);
    if (x >= y) return JSON_TRUE;
    return JSON_FALSE;
}

string prn(list args) {
    string s = "";
    integer i;
    for (i=0; i<llGetListLength(args); i++) {
        if (i > 0) s += " ";
        s += pr_str(llList2String(args,i));
    }
    llOwnerSay(s);
    return JSON_NULL;
}
*/

string run(integer id) {
    if (FN_PRSTR == id) return pr_str();
    if (FN_ADD == id)   return add();
    if (FN_SUB == id)   return subtract();
    if (FN_MUL == id)   return multiply();
    if (FN_DIV == id)   return divide();
    if (FN_LIST_QMARK == id) return list_qmark();
    if (FN_EMPTY_QMARK == id) return empty_qmark();
    if (FN_COUNT == id) return count();
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
            llOwnerSay("core: args="+args_str);
            string data = run(id);
            if (JSON_INVALID == data) {
                send_native_resp(tag, JSON_FALSE, core_error_message);
            } else {
                send_native_resp(tag, JSON_TRUE, data);
            }
            free();
            llOwnerSay("core: ready ("+(string)llGetFreeMemory()+")");
        }
    }
}
