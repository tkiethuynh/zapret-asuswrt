<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta http-equiv="X-UA-Compatible" content="IE=Edge">
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="-1">
<link rel="shortcut icon" href="images/favicon.png">
<link rel="icon" href="images/favicon.png">
<title>WAN - Zapret DPI Bypass</title>
<link rel="stylesheet" type="text/css" href="index_style.css">
<link rel="stylesheet" type="text/css" href="form_style.css">
<script type="text/javascript" src="/js/jquery.js"></script>
<script type="text/javascript" src="/js/httpApi.js"></script>
<script type="text/javascript" src="/state.js"></script>
<script type="text/javascript" src="/general.js"></script>
<script type="text/javascript" src="/popup.js"></script>
<script type="text/javascript" src="/help.js"></script>
<script type="text/javascript" src="/client_function.js"></script>
<script type="text/javascript" src="/validator.js"></script>
<script type="text/javascript" src="/user/zapret/config.js"></script>
<script>
var custom_settings = <% get_custom_settings(); %> || {};

var config = window.zapret_config || {
    enabled: "0",
    mode: "nfqws",
    tpws_enabled: "0",
    tpws_port: "10080",
    tpws_args: "--fooling=md5sig",
    nfqws_enabled: "0",
    nfqws_args: "--fooling=md5sig",
    nfqws_queue: "200",
    hostlist_mode: "all"
};

function SetCurrentPage() {
    document.form.next_page.value = window.location.pathname.substring(1);
    document.form.current_page.value = window.location.pathname.substring(1);
}

function initial() {
    SetCurrentPage();
    show_menu();
    
    if (config.enabled === "1") {
        $("#ui_zapret_mode").val(config.mode);
    } else {
        $("#ui_zapret_mode").val("disabled");
    }
    
    $("#ui_tpws_port").val(config.tpws_port || "10080");
    $("#ui_tpws_args").val(config.tpws_args || "--fooling=md5sig");
    $("#ui_nfqws_queue").val(config.nfqws_queue || "200");
    $("#ui_nfqws_args").val(config.nfqws_args || "--fooling=md5sig");
    $("#ui_hostlist_mode").val(config.hostlist_mode || "all");
    
    $.ajax({
        url: "/user/zapret/hostlist.json",
        dataType: "text",
        success: function(data) {
            $("#ui_hostlist_txt").val(data);
        },
        error: function() {
            $("#ui_hostlist_txt").val("");
        }
    });
        
    changeMode();
}


function changeMode() {
    var modeVal = $("#ui_zapret_mode").val();
    if (modeVal === "disabled") {
        $("#tr_hostlist_mode").hide();
        $("#tr_hostlist_txt").hide();
        $("#tr_tpws_port").hide();
        $("#tr_tpws_args").hide();
        $("#tr_nfqws_queue").hide();
        $("#tr_nfqws_args").hide();
    } else if (modeVal === "tpws") {
        $("#tr_hostlist_mode").show();
        changeHostlistMode();
        $("#tr_tpws_port").show();
        $("#tr_tpws_args").show();
        $("#tr_nfqws_queue").hide();
        $("#tr_nfqws_args").hide();
    } else if (modeVal === "nfqws") {
        $("#tr_hostlist_mode").show();
        changeHostlistMode();
        $("#tr_tpws_port").hide();
        $("#tr_tpws_args").hide();
        $("#tr_nfqws_queue").show();
        $("#tr_nfqws_args").show();
    }
}

function changeHostlistMode() {
    var modeVal = $("#ui_zapret_mode").val();
    if (modeVal === "disabled") {
        $("#tr_hostlist_txt").hide();
        return;
    }
    var hostlistMode = $("#ui_hostlist_mode").val();
    if (hostlistMode === "custom") {
        $("#tr_hostlist_txt").show();
    } else {
        $("#tr_hostlist_txt").hide();
    }
}

function applyRule() {
    var modeVal = $("#ui_zapret_mode").val();
    var enabled = "0";
    var mode = "nfqws";
    var tpws_enabled = "0";
    var nfqws_enabled = "0";
    
    if (modeVal === "tpws") {
        enabled = "1";
        mode = "tpws";
        tpws_enabled = "1";
        
        var port = parseInt($("#ui_tpws_port").val(), 10);
        if (isNaN(port) || port < 1 || port > 65535) {
            alert("Please enter a valid port number (1-65535) for tpws.");
            return;
        }
    } else if (modeVal === "nfqws") {
        enabled = "1";
        mode = "nfqws";
        nfqws_enabled = "1";
        
        var queue = parseInt($("#ui_nfqws_queue").val(), 10);
        if (isNaN(queue) || queue < 1 || queue > 65535) {
            alert("Please enter a valid queue number (1-65535) for nfqws.");
            return;
        }
    }
    
    var hostlistMode = $("#ui_hostlist_mode").val();
    var cleanList = "";
    
    if (hostlistMode === "custom") {
        var rawList = $("#ui_hostlist_txt").val() || "";
        cleanList = rawList.split("\n")
            .map(function(line) { return line.trim(); })
            .filter(function(line) { return line.length > 0 && !line.startsWith("#"); })
            .join(",");
    }
    
    // Package custom settings into the required amng_custom JSON variable
    custom_settings["zapret_enabled"] = enabled;
    custom_settings["zapret_mode"] = mode;
    custom_settings["zapret_tpws_enabled"] = tpws_enabled;
    custom_settings["zapret_tpws_port"] = $("#ui_tpws_port").val();
    custom_settings["zapret_tpws_args"] = $("#ui_tpws_args").val();
    custom_settings["zapret_nfqws_enabled"] = nfqws_enabled;
    custom_settings["zapret_nfqws_args"] = $("#ui_nfqws_args").val();
    custom_settings["zapret_nfqws_queue"] = $("#ui_nfqws_queue").val();
    custom_settings["zapret_hostlist_mode"] = hostlistMode;
    custom_settings["zapret_hostlist_raw"] = cleanList;
    
    document.getElementById('amng_custom').value = JSON.stringify(custom_settings);
    
    showLoading(5);
    document.form.submit();
}
</script>
</head>

<body onload="initial();" class="bg">
<div id="TopBanner"></div>
<div id="Loading" class="popup_bg"></div>
<iframe name="hidden_frame" id="hidden_frame" src="" width="0" height="0" frameborder="0"></iframe>
<form method="post" name="form" action="start_apply.htm" target="hidden_frame">
<input type="hidden" name="current_page" value="%%USER_ASP%%">
<input type="hidden" name="next_page" value="%%USER_ASP%%">
<input type="hidden" name="group_id" value="">
<input type="hidden" name="modified" value="0">
<input type="hidden" name="action_mode" value="apply">
<input type="hidden" name="action_wait" value="5">
<input type="hidden" name="first_time" value="">
<input type="hidden" name="action_script" value="zapret">
<input type="hidden" name="preferred_lang" id="preferred_lang" value="<% nvram_get("preferred_lang"); %>">
<input type="hidden" name="firmver" value="<% nvram_get("firmver"); %>">
<input type="hidden" name="amng_custom" id="amng_custom" value="">

<!-- Custom Settings hidden inputs -->
<input type="hidden" name="zapret_enabled" id="zapret_enabled" value="">
<input type="hidden" name="zapret_mode" id="zapret_mode" value="">
<input type="hidden" name="zapret_tpws_enabled" id="zapret_tpws_enabled" value="">
<input type="hidden" name="zapret_tpws_port" id="zapret_tpws_port" value="">
<input type="hidden" name="zapret_tpws_args" id="zapret_tpws_args" value="">
<input type="hidden" name="zapret_nfqws_enabled" id="zapret_nfqws_enabled" value="">
<input type="hidden" name="zapret_nfqws_args" id="zapret_nfqws_args" value="">
<input type="hidden" name="zapret_nfqws_queue" id="zapret_nfqws_queue" value="">
<input type="hidden" name="zapret_hostlist_mode" id="zapret_hostlist_mode" value="">
<input type="hidden" name="zapret_hostlist_raw" id="zapret_hostlist_raw" value="">

<table class="content" align="center" cellpadding="0" cellspacing="0">
  <tr>
    <td width="17">&nbsp;</td>
    <td valign="top" width="202">
      <div id="mainMenu"></div>
      <div id="subMenu"></div>
    </td>
    <td valign="top">
      <div id="tabMenu" class="submenuBlock"></div>
      <table width="98%" border="0" align="left" cellpadding="0" cellspacing="0">
        <tr>
          <td align="left" valign="top">
            <table width="760px" border="0" cellpadding="5" cellspacing="0" bordercolor="#6b8fa3" class="FormTitle" id="FormTitle">
              <tr>
                <td bgcolor="#4D595D" colspan="3" valign="top">
                  <div>&nbsp;</div>
                  <div class="formfonttitle">WAN - Zapret DPI Bypass</div>
                  <div style="margin:10px 0 10px 5px;" class="splitLine"></div>
                  
                  <div class="noteBlock">
                    <table width="100%" border="0" cellpadding="0" cellspacing="0">
                      <tr>
                        <td valign="top">
                          <div style="font-size:12px; font-weight:bold; color:#FFF; margin-bottom:5px;">DNS Security Warning:</div>
                          <div style="font-size:11px; color:#B0C0C5; line-height:15px;">
                            To ensure Zapret bypasses DPI successfully, it is highly recommended to configure <b>DNS over TLS (DoT)</b> or secure DNS under the router's <a href="Advanced_WAN_Content.asp" style="color:#FFF; text-decoration:underline;">WAN settings page</a>. This prevents ISP DNS hijacking and pollution from interfering with DPI bypass.
                          </div>
                        </td>
                      </tr>
                    </table>
                  </div>
                  
                  <div style="margin:10px 0 10px 5px;" class="splitLine"></div>
                  
                  <table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3" class="FormTable">
                    <thead>
                      <tr>
                        <td colspan="2">Zapret Settings</td>
                      </tr>
                    </thead>
                    
                    <tr>
                      <th width="30%">Bypass Mode</th>
                      <td>
                        <select id="ui_zapret_mode" class="input_option" onchange="changeMode();">
                          <option value="disabled">Disabled</option>
                          <option value="tpws">tpws (Transparent Proxy Mode)</option>
                          <option value="nfqws">nfqws (NFQUEUE Mode)</option>
                        </select>
                      </td>
                    </tr>
                    
                    <tr id="tr_hostlist_mode">
                      <th>DPI Bypass Target</th>
                      <td>
                        <select id="ui_hostlist_mode" class="input_option" onchange="changeHostlistMode();">
                          <option value="all">All Websites</option>
                          <option value="custom">Specific Websites</option>
                        </select>
                      </td>
                    </tr>
                    
                    <tr id="tr_hostlist_txt">
                      <th>Specific Website Domains<br/><small>(One domain per line)</small></th>
                      <td>
                        <textarea id="ui_hostlist_txt" class="input_text_table" rows="8" style="width:98%; font-family:monospace; background-color:#2F3A3E; color:#FFF; border:1px solid #566D7E;"></textarea>
                      </td>
                    </tr>
                    
                    <tr id="tr_tpws_port">
                      <th>tpws Port</th>
                      <td>
                        <input type="text" id="ui_tpws_port" class="input_6_table" maxlength="5" value="10080">
                      </td>
                    </tr>
                    
                    <tr id="tr_tpws_args">
                      <th>tpws Arguments</th>
                      <td>
                        <input type="text" id="ui_tpws_args" class="input_32_table" style="width: 400px;" value="--fooling=md5sig">
                      </td>
                    </tr>
                    
                    <tr id="tr_nfqws_queue">
                      <th>nfqws Queue Number</th>
                      <td>
                        <input type="text" id="ui_nfqws_queue" class="input_6_table" maxlength="5" value="200">
                      </td>
                    </tr>
                    
                    <tr id="tr_nfqws_args">
                      <th>nfqws Arguments</th>
                      <td>
                        <input type="text" id="ui_nfqws_args" class="input_32_table" style="width: 400px;" value="--fooling=md5sig">
                      </td>
                    </tr>
                  </table>
                  
                  <div class="apply_gen">
                    <input class="button_gen" type="button" onclick="applyRule();" value="Apply">
                  </div>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </td>
    <td width="10" align="center" valign="top"></td>
  </tr>
</table>
</form>
<div id="footer"></div>
</body>
</html>
