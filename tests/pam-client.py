#!/usr/bin/env python3
"""Minimal PAM client for tests/pam-polkit.sh (runs inside its bwrap
sandbox, never against the real system): pam_authenticate for one service
and user with a scripted conversation, prints the PAM result name.

  pam-client.py <service> <user> cancel      conversation fails (agent closed)
  pam-client.py <service> <user> pw:<text>    answers every prompt with <text>
"""
import ctypes
import ctypes.util
import sys

PAM_SUCCESS, PAM_CONV_ERR = 0, 19
PAM_PROMPT_ECHO_OFF, PAM_PROMPT_ECHO_ON = 1, 2
NAMES = {0: "SUCCESS", 7: "AUTH_ERR", 9: "AUTHINFO_UNAVAIL", 10: "USER_UNKNOWN",
         11: "MAXTRIES", 19: "CONV_ERR", 20: "AUTHTOK_ERR", 4: "SYSTEM_ERR", 6: "PERM_DENIED"}

libpam = ctypes.CDLL(ctypes.util.find_library("pam"))
libc = ctypes.CDLL(ctypes.util.find_library("c"))
libc.calloc.restype = ctypes.c_void_p
libc.strdup.restype = ctypes.c_void_p
libc.strdup.argtypes = [ctypes.c_char_p]


class Message(ctypes.Structure):
    _fields_ = [("msg_style", ctypes.c_int), ("msg", ctypes.c_char_p)]


class Response(ctypes.Structure):
    _fields_ = [("resp", ctypes.c_void_p), ("resp_retcode", ctypes.c_int)]


CONV = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.POINTER(Message)),
                        ctypes.POINTER(ctypes.POINTER(Response)), ctypes.c_void_p)


class Conv(ctypes.Structure):
    _fields_ = [("conv", CONV), ("appdata_ptr", ctypes.c_void_p)]


service, user, mode = sys.argv[1], sys.argv[2], sys.argv[3]
prompts = 0


@CONV
def conversation(n, msgs, resp, _data):
    global prompts
    if mode == "cancel":
        # what polkit-agent-helper-1 returns when the agent's socket is closed
        return PAM_CONV_ERR
    answer = mode[3:].encode()
    arr = libc.calloc(n, ctypes.sizeof(Response))
    out = ctypes.cast(arr, ctypes.POINTER(Response))
    for i in range(n):
        if msgs[i].contents.msg_style in (PAM_PROMPT_ECHO_OFF, PAM_PROMPT_ECHO_ON):
            prompts += 1
            out[i].resp = libc.strdup(answer)
    resp[0] = out
    return PAM_SUCCESS


handle = ctypes.c_void_p()
conv = Conv(conversation, None)
rc = libpam.pam_start(service.encode(), user.encode(), ctypes.byref(conv), ctypes.byref(handle))
if rc != PAM_SUCCESS:
    print(f"start-failed {rc}")
    sys.exit(2)
# no 2 s failure delay in tests (PAM_FAIL_DELAY item = a no-op callback)
DELAY = ctypes.CFUNCTYPE(None, ctypes.c_int, ctypes.c_uint, ctypes.c_void_p)
nodelay = DELAY(lambda status, usec, data: None)
libpam.pam_set_item(handle, 10, ctypes.cast(nodelay, ctypes.c_void_p))
rc = libpam.pam_authenticate(handle, 0)
libpam.pam_end(handle, rc)
print(NAMES.get(rc, str(rc)), f"prompts={prompts}")
