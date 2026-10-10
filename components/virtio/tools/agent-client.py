#!/usr/bin/env python3
"""Standard QEMU guest-agent Unix-socket client; no request replay after timeout."""
import argparse
import base64
import hashlib
import json
import os
import secrets
import socket
import time
import tempfile
import sys
from pathlib import Path
from pathlib import PurePosixPath
import stat

class AgentError(RuntimeError):
    pass
class CommandError(AgentError):
    """A standard error response; the synchronized connection remains usable."""

class GuestAgent:
    def __init__(self,path,timeout=15):
        if not 0<timeout<=300:raise ValueError('Timeout must be greater than zero and at most 300 seconds')
        self.path=str(path);self.timeout=timeout;self.sock=None;self.buffer=bytearray();self.counter=0;self.nonce=None

    def close(self):
        if self.sock:self.sock.close()
        self.sock=None;self.buffer.clear()

    def __enter__(self):
        try:
            self.sock=socket.socket(socket.AF_UNIX);self.sock.settimeout(self.timeout);self.sock.connect(self.path)
            self.synchronize();return self
        except BaseException:
            self.close();raise

    def __exit__(self,*args):self.close()

    def remaining(self,deadline):
        remaining=deadline-time.monotonic()
        if remaining<=0:raise TimeoutError('Guest-agent deadline expired')
        self.sock.settimeout(remaining)

    def receive(self,deadline,delimited=False):
        if delimited:
            while True:
                try:index=self.buffer.index(255)
                except ValueError:self.buffer.clear()
                else:
                    del self.buffer[:index+1];break
                self.remaining(deadline);data=self.sock.recv(4096)
                if not data:raise EOFError('Guest agent disconnected before sync')
                self.buffer.extend(data)
        while b'\n' not in self.buffer:
            self.remaining(deadline);data=self.sock.recv(4096)
            if not data:raise EOFError('Guest agent disconnected mid-response')
            self.buffer.extend(data)
            if len(self.buffer)>131072:raise AgentError('Guest-agent response exceeds the client bound')
        index=self.buffer.index(10);data=bytes(self.buffer[:index]);del self.buffer[:index+1]
        duplicate_delimited=not delimited and data.startswith(b'\xff')
        if duplicate_delimited:data=data[1:]
        value=json.loads(data)
        if duplicate_delimited and value!={'return':self.nonce,'id':0}:
            raise AgentError('Unexpected delimited response outside synchronization')
        if not isinstance(value,dict):raise AgentError('Guest-agent response is not an object')
        return value

    def synchronize(self):
        self.nonce=secrets.randbits(63);deadline=time.monotonic()+self.timeout
        data=b'\xff'+json.dumps({'execute':'guest-sync-delimited','arguments':{'id':self.nonce},'id':0},separators=(',',':')).encode()+b'\n'
        while time.monotonic()<deadline:
            self.remaining(deadline);self.sock.sendall(data)
            try:response=self.receive(min(deadline,time.monotonic()+1),delimited=True)
            except socket.timeout:continue
            if response=={'return':self.nonce,'id':0}:return
        raise TimeoutError('Guest-agent synchronization failed')

    def request(self,command,arguments=None):
        if not self.sock:raise AgentError('Guest agent is not connected')
        self.counter+=1;data={'execute':command,'id':self.counter}
        if arguments is not None:data['arguments']=arguments
        deadline=time.monotonic()+self.timeout
        try:
            self.remaining(deadline);self.sock.sendall(json.dumps(data,separators=(',',':')).encode()+b'\n')
            while True:
                response=self.receive(deadline)
                if response=={'return':self.nonce,'id':0}:continue
                if response.get('id')!=self.counter:raise AgentError('Guest-agent response ID does not match the request')
                if 'error' in response:
                    error=response['error'];raise CommandError(str(error.get('class','Error'))+': '+str(error.get('desc','Guest request failed')))
                if 'return' not in response:raise AgentError('Guest-agent response has no result')
                return response['return']
        except CommandError:raise
        except BaseException:
            # Request may have executed: never reconnect/replay implicitly.
            self.close();raise

    def download(self,guest_path,destination,checksum=None,transfer_timeout=300):
        """Stream into a local temporary file, then atomically replace destination."""
        if not 0<transfer_timeout<=3600:raise ValueError('Transfer timeout must be 0 through 3600 seconds, excluding zero')
        if checksum is not None and (len(checksum)!=64 or any(c not in '0123456789abcdefABCDEF' for c in checksum)):
            raise ValueError('Expected SHA256 must be 64 hex digits')
        destination=Path(destination);deadline=time.monotonic()+transfer_timeout
        fd,name=tempfile.mkstemp(prefix='.'+destination.name+'.part-',dir=destination.parent)
        handle=None;total=0;digest=hashlib.sha256()
        def call(command,args):
            saved=self.timeout;remaining=deadline-time.monotonic()
            if remaining<=0:raise TimeoutError('File-transfer deadline expired')
            self.timeout=min(saved,remaining)
            try:return self.request(command,args)
            finally:self.timeout=saved
        try:
            with os.fdopen(fd,'wb') as output:
                handle=call('guest-file-open',{'path':str(guest_path),'mode':'r'})
                if type(handle) is not int or handle<=0:raise AgentError('Invalid guest file handle')
                while True:
                    value=call('guest-file-read',{'handle':handle,'count':32768})
                    if not isinstance(value,dict) or type(value.get('count')) is not int or type(value.get('eof')) is not bool:
                        raise AgentError('Malformed guest-file-read result')
                    piece=base64.b64decode(value['buf-b64'],validate=True)
                    if len(piece)!=value['count'] or len(piece)>32768 or (not piece and not value['eof']):
                        raise AgentError('Invalid guest file byte count or EOF')
                    output.write(piece);digest.update(piece);total+=len(piece)
                    if value['eof']:break
                if checksum is not None and digest.hexdigest()!=checksum.lower():raise AgentError('Downloaded SHA256 does not match')
                call('guest-file-close',{'handle':handle});handle=None
                output.flush();os.fsync(output.fileno())
            os.replace(name,destination)
            return {'bytes':total,'sha256':digest.hexdigest(),'destination':str(destination)}
        finally:
            if handle is not None and self.sock:
                try:self.request('guest-file-close',{'handle':handle})
                except Exception:self.close()
            try:os.unlink(name)
            except FileNotFoundError:pass

    def execute(self,path,args=None,env=None,input_data=None,capture_output=True,execution_timeout=300):
        """Run and collect a command on this connection; never replay a launch."""
        if not 0<execution_timeout<=3600:raise ValueError('Execution timeout must be greater than zero and at most 3600 seconds')
        arguments={'path':str(path),'capture-output':capture_output}
        if args is not None:arguments['arg']=list(args)
        if env is not None:arguments['env']=list(env)
        if input_data is not None:
            if len(input_data)>32768:raise ValueError('Command stdin is limited to 32768 bytes; use file transfer for larger inputs')
            arguments['input-data']=base64.b64encode(input_data).decode()
        deadline=time.monotonic()+execution_timeout
        def call(command,args):
            remaining=deadline-time.monotonic()
            if remaining<=0:raise TimeoutError('Guest command deadline expired')
            saved=self.timeout;self.timeout=min(saved,remaining)
            try:return self.request(command,args)
            finally:self.timeout=saved
        try:
            launch=call('guest-exec',arguments)
            if not isinstance(launch,dict) or type(launch.get('pid')) is not int or launch['pid']<=0:raise AgentError('Invalid guest-exec process ID')
            while True:
                value=call('guest-exec-status',{'pid':launch['pid']})
                if not isinstance(value,dict) or type(value.get('exited')) is not bool:raise AgentError('Malformed guest-exec-status result')
                if value['exited']:
                    if (type(value.get('exitcode')) is int)==(type(value.get('signal')) is int):raise AgentError('Guest command has no unambiguous exit status')
                    value['stdout']=base64.b64decode(value.get('out-data',''),validate=True)
                    value['stderr']=base64.b64decode(value.get('err-data',''),validate=True)
                    return value
                time.sleep(min(.05,max(0,deadline-time.monotonic())))
        except BaseException:
            # Disconnect invalidates the operation and cleans owned children.
            self.close();raise

    def shutdown(self,mode='halt',wait_for_error=True):
        """Submit a standard no-success-response request, not proof of shutdown."""
        if mode not in ('halt','reboot'):raise ValueError('OPENSTEP supports halt or reboot')
        info=self.request('guest-info')
        if not any(c.get('name')=='guest-shutdown' and c.get('enabled') and c.get('success-response') is False for c in info.get('supported_commands',[])):
            raise AgentError('Guest agent does not advertise shutdown support')
        self.counter+=1;deadline=time.monotonic()+self.timeout
        self.remaining(deadline)
        self.sock.sendall(json.dumps({'execute':'guest-shutdown','arguments':{'mode':mode},'id':self.counter},separators=(',',':')).encode()+b'\n')
        if wait_for_error:
            # Keep the channel open while the guest consumes this no-response
            # request. Closing immediately can discard its queued input. A
            # caller monitoring QMP may disable this wait but must hold the
            # connection until it observes halt/reboot itself.
            try:
                response=self.receive(deadline)
                if 'error' in response:raise CommandError(str(response['error']))
                raise AgentError('Unexpected success response to guest-shutdown')
            except (socket.timeout,EOFError):pass
        return {'submitted':True,'mode':mode,'completion_confirmed':False}

    def upload(self,source,guest_path,mode=None,transfer_timeout=300,helper='/usr/local/libexec/openstep-agent-file'):
        """Verify a temporary guest file, then commit using an atomic rename."""
        if not 0<transfer_timeout<=3600:raise ValueError('Transfer timeout must be greater than zero and at most 3600 seconds')
        target=PurePosixPath(guest_path)
        if not target.is_absolute() or not target.name or target.name in ('.','..') or str(guest_path).endswith('/'):
            raise ValueError('Upload destination must be an absolute file path')
        temporary=str(target.parent/('.qga-upload-'+secrets.token_hex(16)))
        if len(str(target).encode())>=1024 or len(temporary.encode())>=1024:raise ValueError('Guest path exceeds the native path limit')
        if mode is not None and (type(mode) is not int or not 0<=mode<=0o777):raise ValueError('File mode must be 0000 through 0777')
        deadline=time.monotonic()+transfer_timeout;handle=None;created=False;committed=False
        def call(command,args):
            remaining=deadline-time.monotonic()
            if remaining<=0:raise TimeoutError('Upload deadline expired')
            saved=self.timeout;self.timeout=min(saved,remaining)
            try:return self.request(command,args)
            finally:self.timeout=saved
        def run(path,args):
            remaining=deadline-time.monotonic()
            if remaining<=0:raise TimeoutError('Upload deadline expired')
            result=self.execute(path,args,execution_timeout=min(remaining,3600))
            if result.get('exitcode')!=0:raise AgentError('Upload helper failed: '+result['stderr'].decode(errors='replace'))
        def identity(value):return value.st_dev,value.st_ino,value.st_size,value.st_mtime_ns,value.st_ctime_ns
        try:
            with open(source,'rb') as input_file:
                before=os.fstat(input_file.fileno())
                if not stat.S_ISREG(before.st_mode) or before.st_size>2147483647:raise ValueError('Upload requires a regular file of at most 2 GiB minus one byte')
                selected_mode=(before.st_mode&0o777) if mode is None else mode
                run(helper,['probe'])
                handle=call('guest-file-open',{'path':temporary,'mode':'w+'});created=True
                if type(handle) is not int or handle<=0:raise AgentError('Invalid guest file handle')
                run('chmod',['600',temporary])
                total=0;digest=hashlib.sha256()
                while total<before.st_size:
                    piece=input_file.read(min(32768,before.st_size-total))
                    if not piece:raise AgentError('Upload source was shortened')
                    offset=0
                    while offset<len(piece):
                        value=call('guest-file-write',{'handle':handle,'buf-b64':base64.b64encode(piece[offset:]).decode()})
                        if not isinstance(value,dict) or type(value.get('count')) is not int or not 0<value['count']<=len(piece)-offset or value.get('eof') is not False:
                            raise AgentError('Invalid or failed guest file write')
                        count=value['count'];digest.update(piece[offset:offset+count]);offset+=count;total+=count
                call('guest-file-flush',{'handle':handle})
                call('guest-file-seek',{'handle':handle,'offset':0,'whence':'set'})
                verified=hashlib.sha256();verified_bytes=0
                while True:
                    value=call('guest-file-read',{'handle':handle,'count':32768})
                    if not isinstance(value,dict) or type(value.get('count')) is not int or type(value.get('eof')) is not bool:raise AgentError('Malformed upload verification reply')
                    piece=base64.b64decode(value['buf-b64'],validate=True)
                    if len(piece)!=value['count'] or len(piece)>32768 or not piece and not value['eof']:raise AgentError('Invalid upload verification byte count')
                    verified.update(piece);verified_bytes+=len(piece)
                    if verified_bytes>total:raise AgentError('Guest temporary file unexpectedly grew')
                    if value['eof']:break
                if verified_bytes!=total or verified.digest()!=digest.digest():raise AgentError('Guest upload SHA256 does not match')
                call('guest-file-close',{'handle':handle});handle=None
                if identity(before)!=identity(os.fstat(input_file.fileno())):raise AgentError('Upload source changed before commit')
                run(helper,['commit',temporary,str(target),format(selected_mode,'o')]);committed=True
                return {'bytes':total,'sha256':digest.hexdigest(),'destination':str(target),'mode':format(selected_mode,'04o')}
        finally:
            if handle is not None and self.sock:
                try:self.request('guest-file-close',{'handle':handle})
                except Exception:self.close()
            if created and not committed:
                # Only remove this operation's random temporary path. Never
                # replay commit or delete the intended destination after error.
                try:
                    if self.sock:self.execute(helper,['remove',temporary],execution_timeout=10)
                    else:
                        with GuestAgent(self.path,min(self.timeout,5)) as cleanup:
                            cleanup.execute(helper,['remove',temporary],execution_timeout=10)
                except Exception:pass

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--socket',required=True);parser.add_argument('--timeout',type=float,default=15)
    parser.add_argument('command',help='QGA command name, or download');parser.add_argument('paths',nargs='*')
    parser.add_argument('--arguments',type=json.loads);parser.add_argument('--sha256')
    parser.add_argument('--transfer-timeout',type=float,default=300)
    parser.add_argument('--execution-timeout',type=float,default=300);parser.add_argument('--env',action='append')
    parser.add_argument('--mode',type=lambda text:int(text,8));parser.add_argument('--file-helper',default='/usr/local/libexec/openstep-agent-file')
    args=parser.parse_args()
    with GuestAgent(args.socket,args.timeout) as agent:
        if args.command=='shutdown':
            if len(args.paths)>1 or args.arguments is not None:parser.error('shutdown accepts halt or reboot')
            result=agent.shutdown(args.paths[0] if args.paths else 'halt')
        elif args.command=='exec':
            if not args.paths or args.arguments is not None:parser.error('exec requires PROGRAM [ARGS ...]; use -- before program flags')
            result=agent.execute(args.paths[0],args.paths[1:],env=args.env,execution_timeout=args.execution_timeout)
            sys.stdout.buffer.write(result['stdout']);sys.stdout.buffer.flush()
            sys.stderr.buffer.write(result['stderr']);sys.stderr.buffer.flush()
            if result.get('out-truncated') or result.get('err-truncated'):print('Guest command output was truncated',file=sys.stderr)
            return result.get('exitcode',128+result.get('signal',0))
        elif args.command=='upload':
            if len(args.paths)!=2 or args.arguments is not None:parser.error('upload requires HOST_PATH GUEST_PATH')
            result=agent.upload(*args.paths,mode=args.mode,transfer_timeout=args.transfer_timeout,helper=args.file_helper)
        elif args.command=='download':
            if len(args.paths)!=2 or args.arguments is not None:parser.error('download requires GUEST_PATH HOST_PATH')
            result=agent.download(*args.paths,checksum=args.sha256,transfer_timeout=args.transfer_timeout)
        else:
            if args.paths or args.sha256 is not None:parser.error('QGA calls use --arguments, without paths or --sha256')
            result=agent.request(args.command,args.arguments)
        print(json.dumps(result,indent=2))

if __name__=='__main__':sys.exit(main())
