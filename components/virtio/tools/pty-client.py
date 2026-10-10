#!/usr/bin/env python3
"""Interactive OPENSTEP PTY client. Ctrl-] disconnects; no session replay."""
import argparse
import fcntl
import os
import secrets
import select
import signal
import socket
import struct
import sys
import termios
import time
import tty
MAGIC=b'OS42PTY1';HELLO,READY,INPUT,OUTPUT,RESIZE,CLOSE,EXIT,ERROR,PING,PONG=range(1,11)
def encode(kind,payload=b''):
    if not 1<=kind<=10 or len(payload)>4096:raise ValueError('Invalid PTY frame')
    return MAGIC+struct.pack('<II',kind,len(payload))+payload
def take(buffer):
    if len(buffer)<16:return None
    if buffer[:8]!=MAGIC:raise RuntimeError('Invalid PTY frame magic')
    kind,count=struct.unpack_from('<II',buffer,8)
    if not 1<=kind<=10 or count>4096:raise RuntimeError('Invalid PTY frame header')
    if len(buffer)<16+count:return None
    value=kind,bytes(buffer[16:16+count]);del buffer[:16+count];return value
class PtyClient:
    def __init__(self,path,rows=24,columns=80,timeout=10):
        if not 1<=rows<=4096 or not 1<=columns<=4096 or not 0<timeout<=300:raise ValueError('Invalid terminal size/timeout')
        self.path=str(path);self.rows=rows;self.columns=columns;self.timeout=timeout;self.sock=None;self.buffer=bytearray();self.cookie=secrets.token_bytes(8);self.pid=None
    def close(self):
        if self.sock:self.sock.close()
        self.sock=None
    def __enter__(self):
        try:
            self.sock=socket.socket(socket.AF_UNIX);self.sock.settimeout(self.timeout);self.sock.connect(self.path)
            deadline=time.monotonic()+self.timeout
            hello=encode(HELLO,self.cookie+struct.pack('<HH',self.rows,self.columns))
            while time.monotonic()<deadline:
                self.sock.sendall(hello)
                try:
                    while True:
                        kind,payload=self.receive(min(deadline,time.monotonic()+1))
                        if kind==ERROR:raise RuntimeError(payload.decode(errors='replace'))
                        if kind==READY:
                            if len(payload)!=12 or payload[:8]!=self.cookie:raise RuntimeError('PTY session cookie mismatch')
                            self.pid=struct.unpack_from('<I',payload,8)[0];return self
                except socket.timeout:continue
            raise TimeoutError('PTY startup timed out')
        except BaseException:self.close();raise
    def __exit__(self,*args):self.close()
    def receive(self,deadline=None):
        if deadline is None:deadline=time.monotonic()+self.timeout
        while True:
            value=take(self.buffer)
            if value:return value
            remaining=deadline-time.monotonic()
            if remaining<=0:raise TimeoutError('PTY receive deadline expired')
            self.sock.settimeout(remaining);data=self.sock.recv(4096)
            if not data:raise EOFError('PTY disconnected')
            self.buffer.extend(data)
            if len(self.buffer)>65536:raise RuntimeError('PTY receive buffer exceeded bound')
    def send(self,data):
        self.sock.settimeout(self.timeout)
        for offset in range(0,len(data),4096):self.sock.sendall(encode(INPUT,data[offset:offset+4096]))
    def resize(self,rows,columns):
        if not 1<=rows<=4096 or not 1<=columns<=4096:raise ValueError('Invalid terminal size')
        self.sock.settimeout(self.timeout);self.sock.sendall(encode(RESIZE,struct.pack('<HH',rows,columns)))
def interactive(client,heartbeat_timeout=45):
    if not 1<=heartbeat_timeout<=300:raise ValueError('Keepalive timeout must be 1 through 300 seconds')
    old=termios.tcgetattr(0);in_flags=fcntl.fcntl(0,fcntl.F_GETFL);out_flags=fcntl.fcntl(1,fcntl.F_GETFL)
    prior_handlers={};resized=[True];stopped=[False];outgoing=bytearray();display=bytearray();exit_status=None
    last_pong=last_ping=time.monotonic();ping_interval=min(5,heartbeat_timeout/3)
    def changed(number,frame):resized[0]=True
    def stop(number,frame):stopped[0]=True
    try:
        for number,handler in [(signal.SIGWINCH,changed),(signal.SIGTERM,stop),(signal.SIGHUP,stop)]:
            prior_handlers[number]=signal.getsignal(number);signal.signal(number,handler)
        tty.setraw(0);fcntl.fcntl(0,fcntl.F_SETFL,in_flags|os.O_NONBLOCK);fcntl.fcntl(1,fcntl.F_SETFL,out_flags|os.O_NONBLOCK);client.sock.setblocking(False)
        while not stopped[0]:
            while len(display)<50000:
                packet=take(client.buffer)
                if packet is None:break
                kind,payload=packet
                if kind==OUTPUT:
                    if len(display)+len(payload)>65536:raise RuntimeError('Terminal display buffer full')
                    display.extend(payload)
                elif kind==EXIT:
                    if len(payload)!=8:raise RuntimeError('Invalid PTY exit status')
                    code,number=struct.unpack('<II',payload);exit_status=code if not number else 128+number
                    outgoing.clear()
                elif kind==ERROR:raise RuntimeError(payload.decode(errors='replace'))
                elif kind==PONG:
                    if payload!=client.cookie:raise RuntimeError('PTY keepalive cookie mismatch')
                    last_pong=time.monotonic()
                elif kind!=READY:raise RuntimeError('Unexpected PTY response')
            if exit_status is not None and not display:return exit_status
            now=time.monotonic()
            if exit_status is None:
                if now-last_pong>=heartbeat_timeout:raise TimeoutError('PTY service did not answer keepalive')
                if now-last_ping>=ping_interval and len(outgoing)<60000:
                    outgoing.extend(encode(PING,client.cookie));last_ping=now
            if exit_status is None and resized[0] and len(outgoing)<60000:
                size=os.get_terminal_size(0);outgoing.extend(encode(RESIZE,struct.pack('<HH',min(size.lines,4096),min(size.columns,4096))));resized[0]=False
            reads=[];writes=[]
            if exit_status is None and len(outgoing)<60000:reads.append(0)
            if exit_status is None and len(display)<50000:reads.append(client.sock)
            if outgoing:writes.append(client.sock)
            if display:writes.append(1)
            wait=1
            if exit_status is None:
                wait=min(wait,max(0,last_pong+heartbeat_timeout-time.monotonic()))
                if len(outgoing)<60000:wait=min(wait,max(0,last_ping+ping_interval-time.monotonic()))
            readable,writable,_=select.select(reads,writes,[],wait)
            if 0 in readable:
                data=os.read(0,512)
                if not data or b'\x1d' in data:return 0
                outgoing.extend(encode(INPUT,data))
            if client.sock in readable:
                data=client.sock.recv(4096)
                if not data:raise EOFError('PTY disconnected')
                client.buffer.extend(data)
            if client.sock in writable:
                try:count=client.sock.send(outgoing)
                except BlockingIOError:count=0
                del outgoing[:count]
            if 1 in writable:
                try:count=os.write(1,display)
                except BlockingIOError:count=0
                del display[:count]
        return 0
    finally:
        termios.tcsetattr(0,termios.TCSANOW,old);fcntl.fcntl(0,fcntl.F_SETFL,in_flags);fcntl.fcntl(1,fcntl.F_SETFL,out_flags)
        for number,handler in prior_handlers.items():signal.signal(number,handler)
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--socket',required=True);parser.add_argument('--timeout',type=float,default=10);parser.add_argument('--heartbeat-timeout',type=float,default=45)
    args=parser.parse_args()
    if not os.isatty(0) or not os.isatty(1):parser.error('Interactive use requires a terminal on stdin/stdout')
    size=os.get_terminal_size(0)
    try:
        with PtyClient(args.socket,size.lines,size.columns,args.timeout) as client:return interactive(client,args.heartbeat_timeout)
    except (OSError,EOFError,RuntimeError,TimeoutError,ValueError) as error:
        print('openstep-pty: '+str(error),file=sys.stderr);return 1
if __name__=='__main__':sys.exit(main())
