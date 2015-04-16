key me = NULL_KEY;

// tags for forms
integer LIST = 0;
integer SYMBOL = 1;
integer KEYWORD = 2;
integer VECTOR = 3;
integer HASHMAP = 5;
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
integer FN_EQ = 109;
integer FN_LESS_THAN = 110;
integer FN_LESS_THAN_EQ = 111;
integer FN_GREATER_THAN = 112;
integer FN_GREATER_THAN_EQ = 113;
integer FN_PRN = 114;

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

string math(integer op) {
    float result = llList2Float(args,0);
    integer is_int = 1;
    integer i;
    for (i=1; i < llGetListLength(args); i++) {
        if (op == 0) result += llList2Float(args,i);
        else if (op == 1) result -= llList2Float(args,i);
        else if (op == 2) result *= llList2Float(args,i);
        else if (op == 3) result /= llList2Float(args,i);
        is_int = is_int && llGetListEntryType(args,i) == TYPE_INTEGER;
    }
    if (is_int)
        return (string)((integer)result);
    else
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

string equal(list path_a, list path_b) {
    string x = read_form(args_str, path_a);
    string y = read_form(args_str, path_b);
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
                if (JSON_TRUE != equal(path_a+[i], path_b+[i]))
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

string compare(integer code) {
    if (JSON_NUMBER != llJsonValueType(llList2String(args,0), [])
    ||  JSON_NUMBER != llJsonValueType(llList2String(args,1), [])) {
        return error("Invalid type");
    }
    float x = (float)llList2Float(args,0);
    float y = (float)llList2Float(args,1);
    integer result;
    if (code == FN_LESS_THAN) result = (x < y);
    else if (code == FN_LESS_THAN_EQ) result = (x <= y);
    else if (code == FN_GREATER_THAN) result = (x > y);
    else if (code == FN_GREATER_THAN_EQ) result = (x >= y);

    if (result) return JSON_TRUE;
    else return JSON_FALSE;
}

string prn() {
    string s = "";
    integer i;
    form = args_str;
    for (i=0; i<llGetListLength(args); i++) {
        if (i > 0) s += " ";
        s += _pr_str([i]);
    }
    // use llJsonGetValue to 'unquote' one level
    s = llJsonGetValue("\""+s+"\"",[]);
    llOwnerSay(s);
    return JSON_NULL;
}

string run(integer id) {
    if (FN_PRSTR == id) return pr_str();
    if (FN_ADD <= id && id <= FN_DIV)   return math(id-FN_ADD);
    if (FN_LIST_QMARK == id) return list_qmark();
    if (FN_EMPTY_QMARK == id) return empty_qmark();
    if (FN_COUNT == id) return count();
    if (FN_EQ == id) return equal([0],[1]);
    if (FN_LESS_THAN <= id && id <= FN_GREATER_THAN_EQ) return compare(id);
    if (FN_PRN == id) return prn();
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
