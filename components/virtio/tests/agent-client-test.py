#!/usr/bin/env python3
"""Real Unix-socket tests of sync, framing, IDs, errors and no replay."""
import json
import base64
import hashlib
import runpy
import socket
import tempfile
import threading
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'work/virtio/agent';OUT.mkdir(parents=True,exist_ok=True)
api=runpy.run_path(str(ROOT/'components/virtio/tools/agent-client.py'))
GuestAgent=api['GuestAgent'];CommandError=api['CommandError'];AgentError=api['AgentError']
def request(peer):
    data=bytearray()
    while not data.endswith(b'\n'):
        part=peer.recv(1)
        if not part:raise EOFError('Client closed')
        data.extend(part)
    return json.loads(data.lstrip(b'\xff'))
def send(peer,value,prefix=b''):
    data=prefix+json.dumps(value).encode()+b'\n'
    for offset in range(0,len(data),7):peer.sendall(data[offset:offset+7])
class ClientTests(unittest.TestCase):
    def run_peer(self,serve,check,timeout=1):
        errors=[]
        with tempfile.TemporaryDirectory(dir=OUT) as directory:
            path=Path(directory)/'agent.sock';listener=socket.socket(socket.AF_UNIX)
            listener.bind(str(path));listener.listen(1);listener.settimeout(2)
            def server():
                try:
                    peer,_=listener.accept();peer.settimeout(2)
                    with peer:
                        sync=request(peer);self.assertEqual(sync['execute'],'guest-sync-delimited')
                        nonce=sync['arguments']['id'];self.assertTrue(0<=nonce<2**63)
                        send(peer,{'return':nonce,'id':0},b'stale invalid bytes\xff')
                        serve(peer,nonce)
                except BaseException as exc:errors.append(exc)
            thread=threading.Thread(target=server);thread.start()
            try:
                with GuestAgent(path,timeout) as agent:check(agent)
            finally:
                thread.join(3);listener.close()
            self.assertFalse(thread.is_alive());self.assertFalse(errors,errors)
    def test_fragmentation_duplicate_sync_and_error_connection(self):
        def serve(peer,nonce):
            command=request(peer);send(peer,{'return':nonce,'id':0},b'\xff')
            send(peer,{'error':{'class':'GenericError','desc':'Expected rejection'},'id':command['id']})
            command=request(peer);send(peer,{'return':{},'id':command['id']})
        def check(agent):
            with self.assertRaises(CommandError):agent.request('guest-bad')
            self.assertIsNotNone(agent.sock);self.assertEqual(agent.request('guest-ping'),{})
        self.run_peer(serve,check)
    def test_unexpected_delimited_response_closes_without_replay(self):
        def serve(peer,nonce):
            command=request(peer)
            send(peer,{'return':{},'id':command['id']},b'\xff')
            self.assertEqual(peer.recv(1),b'')
        def check(agent):
            with self.assertRaises(AgentError):agent.request('guest-file-write',{'handle':1,'buf-b64':'AA=='})
            self.assertIsNone(agent.sock)
        self.run_peer(serve,check)
    def test_wrong_id_closes_without_replay(self):
        def serve(peer,nonce):
            command=request(peer);self.assertEqual(command['execute'],'guest-file-write')
            send(peer,{'return':{},'id':command['id']+1});self.assertEqual(peer.recv(1),b'')
        def check(agent):
            with self.assertRaises(AgentError):agent.request('guest-file-write',{'handle':1,'buf-b64':'AA=='})
            self.assertIsNone(agent.sock)
        self.run_peer(serve,check)
    def test_timeout_closes_without_replay(self):
        def serve(peer,nonce):
            self.assertEqual(request(peer)['execute'],'guest-file-write');self.assertEqual(peer.recv(1),b'')
        def check(agent):
            with self.assertRaises(TimeoutError):agent.request('guest-file-write',{'handle':1,'buf-b64':'AA=='})
            self.assertIsNone(agent.sock)
        self.run_peer(serve,check,.1)
    def test_mid_response_eof(self):
        def serve(peer,nonce):request(peer);peer.sendall(b'{"return":')
        def check(agent):
            with self.assertRaises(EOFError):agent.request('guest-ping')
            self.assertIsNone(agent.sock)
        self.run_peer(serve,check)
    def test_download_checksum_and_atomic_replacement(self):
        fixture=bytes(range(256))*160
        def serve(peer,nonce):
            command=request(peer);self.assertEqual(command['execute'],'guest-file-open');send(peer,{'return':1,'id':command['id']})
            for offset in (0,32768):
                command=request(peer);piece=fixture[offset:offset+32768]
                send(peer,{'return':{'count':len(piece),'buf-b64':base64.b64encode(piece).decode(),'eof':offset+len(piece)==len(fixture)},'id':command['id']})
            command=request(peer);self.assertEqual(command['execute'],'guest-file-close');send(peer,{'return':{},'id':command['id']})
        def check(agent):
            with tempfile.TemporaryDirectory(dir=OUT) as directory:
                target=Path(directory)/'result';target.write_bytes(b'old')
                report=agent.download('/guest/file',target,hashlib.sha256(fixture).hexdigest())
                self.assertEqual(target.read_bytes(),fixture);self.assertEqual(report['bytes'],len(fixture));self.assertEqual(list(Path(directory).iterdir()),[target])
        self.run_peer(serve,check)
    def test_download_checksum_failure_preserves_destination(self):
        def serve(peer,nonce):
            command=request(peer);send(peer,{'return':1,'id':command['id']})
            command=request(peer);send(peer,{'return':{'count':1,'buf-b64':'AA==','eof':True},'id':command['id']})
            command=request(peer);self.assertEqual(command['execute'],'guest-file-close');send(peer,{'return':{},'id':command['id']})
        def check(agent):
            with tempfile.TemporaryDirectory(dir=OUT) as directory:
                target=Path(directory)/'result';target.write_bytes(b'original')
                with self.assertRaises(AgentError):agent.download('/guest/file',target,'0'*64)
                self.assertEqual(target.read_bytes(),b'original');self.assertEqual(list(Path(directory).iterdir()),[target])
        self.run_peer(serve,check)
    def test_interrupted_download_preserves_destination(self):
        def serve(peer,nonce):
            command=request(peer);send(peer,{'return':1,'id':command['id']})
            command=request(peer);send(peer,{'return':{'count':1,'buf-b64':'AA==','eof':False},'id':command['id']})
            request(peer);peer.sendall(b'{"return":')
        def check(agent):
            with tempfile.TemporaryDirectory(dir=OUT) as directory:
                target=Path(directory)/'result';target.write_bytes(b'original')
                with self.assertRaises(EOFError):agent.download('/guest/file',target)
                self.assertEqual(target.read_bytes(),b'original');self.assertEqual(list(Path(directory).iterdir()),[target])
        self.run_peer(serve,check)
    def test_execute_polling_binary_output_and_environment(self):
        def serve(peer,nonce):
            command=request(peer);self.assertEqual(command['execute'],'guest-exec')
            self.assertEqual(command['arguments']['env'],['VALUE=test'])
            self.assertEqual(base64.b64decode(command['arguments']['input-data']),b'\0\xff')
            send(peer,{'return':{'pid':123},'id':command['id']})
            command=request(peer);self.assertEqual(command['arguments'],{'pid':123});send(peer,{'return':{'exited':False},'id':command['id']})
            command=request(peer);send(peer,{'return':{'exited':True,'exitcode':7,'out-data':'AP8=','err-data':'ZXJyb3I='},'id':command['id']})
        def check(agent):
            result=agent.execute('/bin/cat',env=['VALUE=test'],input_data=b'\0\xff')
            self.assertEqual(result['exitcode'],7);self.assertEqual(result['stdout'],b'\0\xff');self.assertEqual(result['stderr'],b'error')
        self.run_peer(serve,check)
    def test_execute_deadline_disconnects_without_relaunch(self):
        def serve(peer,nonce):
            command=request(peer);send(peer,{'return':{'pid':123},'id':command['id']})
            while True:
                try:command=request(peer)
                except EOFError:return
                self.assertEqual(command['execute'],'guest-exec-status');send(peer,{'return':{'exited':False},'id':command['id']})
        def check(agent):
            with self.assertRaises(TimeoutError):agent.execute('/bin/sleep',['30'],execution_timeout=.1)
            self.assertIsNone(agent.sock)
        self.run_peer(serve,check)
    def test_shutdown_no_success_response(self):
        def serve(peer,nonce):
            command=request(peer);self.assertEqual(command['execute'],'guest-info')
            send(peer,{'return':{'supported_commands':[{'name':'guest-shutdown','enabled':True,'success-response':False}]},'id':command['id']})
            command=request(peer);self.assertEqual(command['execute'],'guest-shutdown');self.assertEqual(command['arguments'],{'mode':'halt'})
            self.assertEqual(peer.recv(1),b'')
        def check(agent):
            result=agent.shutdown('halt',wait_for_error=False)
            self.assertTrue(result['submitted']);self.assertFalse(result['completion_confirmed']);self.assertIsNotNone(agent.sock)
        self.run_peer(serve,check)
    def test_shutdown_explicit_error(self):
        def serve(peer,nonce):
            command=request(peer);send(peer,{'return':{'supported_commands':[{'name':'guest-shutdown','enabled':True,'success-response':False}]},'id':command['id']})
            command=request(peer);send(peer,{'error':{'class':'GenericError','desc':'Cannot launch shutdown'},'id':command['id']})
        def check(agent):
            with self.assertRaises(CommandError):agent.shutdown('halt')
        self.run_peer(serve,check)
if __name__=='__main__':unittest.main()
