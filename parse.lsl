key me = NULL_KEY;

string input = "";

// MSG_PARSE_REQ format: string
integer MSG_PARSE_REQ = 0;

// MSG_PARSE_RESP format: {"success?":<boolean>,"data":<string or form>}
integer MSG_PARSE_RESP = 1;


// globals used during parsing
list tokens;
integer next_token;
integer num_tokens;
integer parse_error = FALSE;
string parse_error_message = "";

// tags for forms
integer LIST = 0;
integer SYMBOL = 1;
integer KEYWORD = 2;
integer VECTOR = 3;
integer BUILTIN = 4;

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

// [\s,]*
// (~@
// |[\[\]{}()'`~^@]
// |"(?:\\.|[^\\"])*"
// |;.*
// |[^\s\[\]{}('"`,;)]*)

tokenize(string line) {
//    llOwnerSay("tokenize: " + line);
    tokens = llParseString2List(line, [" ","\n","\t"], ["(",")","{","}","[","]","\"",";"]);
    // merge strings, drop comments
    integer pos = 0;
    integer in_string = 0;
    integer escaped = 0;
    string token;
    do {
//        llOwnerSay("tokens: " + llDumpList2String(tokens,","));
        token = llList2String(tokens, pos);
        // stupid llParseString2List doesn't handle backslash spacers
        integer backslash_pos = llSubStringIndex(token, "\\");
        if ("\\" != token && backslash_pos >= 0) {
//            llOwnerSay("found backslash");
            if (backslash_pos == llStringLength(token)-1) {
                tokens = llListReplaceList(tokens, [llGetSubString(token,0,backslash_pos-1),"\\"],pos,pos);
            } else {
                tokens = llListReplaceList(tokens, [llGetSubString(token,0,backslash_pos-1),
                                                    "\\",
                                                    llGetSubString(token,backslash_pos+1,llStringLength(token))],
                                           pos,pos);
            }
            token = llList2String(tokens, pos);
        }
//        llOwnerSay("token: " + token);
        if (in_string == 1) {
            if (escaped == 1) {
                tokens = llListReplaceList(tokens, [llList2String(tokens,pos-1)+token], pos-1,pos);
//                llOwnerSay("escaped="+token);
                escaped = 0;
            } else {
                if ("\"" == token) {
                    in_string = 0;
//                    llOwnerSay("in_string=0");
                    tokens = llListReplaceList(tokens, [requote(llList2String(tokens,pos-1))], pos-1, pos);
                } else  if ("\\" == token) {
//                    llOwnerSay("escaped=1");
                    escaped = 1;
                    //tokens = llListReplaceList(tokens, [], pos, pos);
                    tokens = llListReplaceList(tokens, [llList2String(tokens,pos-1)+token], pos-1,pos);
                } else {
                    tokens = llListReplaceList(tokens, [llList2String(tokens,pos-1)+token], pos-1,pos);
                }
            }
        } else {
            if ("\"" == token) {
//                llOwnerSay("in_string=1");
                in_string = 1;
                tokens = llListReplaceList(tokens, [""], pos, pos);
                pos = pos + 1;
            } else if (";" == token) {
                pos = llGetListLength(tokens);
            } else {
                pos = pos + 1;
            }
        }
    } while (pos < llGetListLength(tokens));
    num_tokens = llGetListLength(tokens);
    next_token = 0;
//    llOwnerSay("tokens: " + llDumpList2String(tokens,","));
}

string consume_token() {
    string token = llList2String(tokens, next_token);
    next_token = next_token + 1;
    return token;
}

string peek_token() {
    return llList2String(tokens, next_token);
}

string set_parse_error(string msg) {
    parse_error = TRUE;
    parse_error_message = msg;
    return "";
}

reset_parse_error() {
    parse_error = FALSE;
    parse_error_message = "";
}

string read_atom() {
    string token = consume_token();
//    llOwnerSay("read_atom: "+token);
    string type = llJsonValueType(token,[]);
    if ((JSON_NUMBER == type && "-" != token) || JSON_STRING == type || JSON_TRUE == type || JSON_FALSE == type ||
        JSON_NULL == type) {
        return token;
    } else if (0 == llSubStringIndex(token,":")) {
        return llList2Json(JSON_ARRAY, [KEYWORD, token]);
    } else {
        return llList2Json(JSON_ARRAY, [SYMBOL, token]);
    }
}

string read_sequence() {
    integer i = 0;
    integer type;
    string stop_token;
    string start = consume_token();
    if ("(" == start) {
        type = LIST;
        stop_token = ")";
    } else if ("[" == start) {
        type = VECTOR;
        stop_token = "]";
    } else {
        return set_parse_error("Not a sequence: "+start);
    }
    string l = llList2Json(JSON_ARRAY, [type]);
    do {
        string token = peek_token();
//        llOwnerSay("read_sequence: "+token+","+l);
        if (stop_token == token) {
            consume_token();
//            llOwnerSay("read_sequence: returning "+l);
            return l;
        } else {
            string f = read_form();
            if (parse_error) return "";
//            llOwnerSay("read_sequence: appending "+f);
            l = llJsonSetValue(l, [JSON_APPEND], f);
        }
    } while (next_token < num_tokens);
    return set_parse_error("Missing " + stop_token);
}

string read_form() {
    string token = peek_token();
//    llOwnerSay("read_form: "+token);
    if ("(" == token || "[" == token) {
        return read_sequence();
    } else {
        return read_atom();
    }
}

/**
 * Parse an input stream, and return a form.
 * A form is a JSON value.
 */
string read_str(string line)
{
    reset_parse_error();
    tokenize(line);
    return read_form();
}

default
{
    state_entry()
    {
        if (me == NULL_KEY) me = llGenerateKey();
        llOwnerSay("parse: ready");
    }
    
    link_message(integer sender, integer num, string str, key id)
    {
//        llOwnerSay("parser: link_message(s="+(string)sender+",num="
//                   +(string)num+",str="+str+",key="+(string)id);
        if (id == me) return;
        if (num == MSG_PARSE_REQ) {
            llOwnerSay("parse: req: "+str);
            string form = read_str(str);
            string resp = "{}";
            if (parse_error) {
                llOwnerSay("parse: failed: "+parse_error_message);
                resp = llJsonSetValue(resp,["success?"], JSON_FALSE);
                resp = llJsonSetValue(resp,["data"], parse_error_message);
            } else {
                resp = llJsonSetValue(resp,["success?"], JSON_TRUE);
                resp = llJsonSetValue(resp,["data"], form);
            }
            llOwnerSay("parser: resp: "+resp);
            llMessageLinked(LINK_THIS, MSG_PARSE_RESP, resp, me);
        }
    }
}
