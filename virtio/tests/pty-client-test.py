#!/usr/bin/env python3
import json
import runpy
import socket
import struct
import tempfile
import threading
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'work/virtio/agent';OUT.mkdir(parents=True,exist_ok=True)
api=runpy.run_path(str(ROOT/'virtio/tools/pty-client.py'));Client=api['PtyClient'];encode=api['encode'];take=api['take']
def receive(peer):
    buffer=bytearray()
    while True:
        value=take(buffer)
        if value:return value
        data=peer.recv(1)
        if not data:raise EOFError
        buffer.extend(data)
class Tests(unittest.TestCase):
    def test_fragmented_handshake_binary_and_resize(self):
        errors=[]
        with tempfile.TemporaryDirectory(dir=OUT) as directory:
            path=Path(directory)/'pty.sock';listener=socket.socket(socket.AF_UNIX);listener.bind(str(path));listener.listen(1)
            def server():
                try:
                    peer,_=listener.accept();peer.settimeout(2)
                    with peer:
                        kind,hello=receive(peer);self.assertEqual(kind,1);self.assertEqual(struct.unpack('<HH',hello[8:]),(30,100))
                        packet=encode(2,hello[:8]+struct.pack('<I',123))
                        for byte in packet:peer.sendall(bytes([byte]))
                        kind,data=receive(peer);self.assertEqual(kind,3);self.assertEqual(data,bytes(range(256)))
                        kind,data=receive(peer);self.assertEqual((kind,struct.unpack('<HH',data)),(5,(40,120)))
                        peer.sendall(encode(4,bytes(range(256)))+encode(7,struct.pack('<II',7,0)))
                except BaseException as exc:errors.append(exc)
            thread=threading.Thread(target=server);thread.start()
            with Client(path,30,100) as client:
                self.assertEqual(client.pid,123);client.send(bytes(range(256)));client.resize(40,120)
                self.assertEqual(client.receive(),(4,bytes(range(256))))
                self.assertEqual(client.receive(),(7,struct.pack('<II',7,0)))
            thread.join(3);listener.close();self.assertFalse(thread.is_alive());self.assertFalse(errors,errors)
    def test_malformed_headers(self):
        for packet in [b'badmagic'+struct.pack('<II',1,0),b'OS42PTY1'+struct.pack('<II',1,4097),b'OS42PTY1'+struct.pack('<II',99,0)]:
            with self.assertRaises(RuntimeError):take(bytearray(packet))
    def test_partial_frames(self):
        packet=encode(4,b'\0\xffOS42PTY1')
        for n in range(len(packet)):self.assertIsNone(take(bytearray(packet[:n])))
        buffer=bytearray(packet);self.assertEqual(take(buffer),(4,b'\0\xffOS42PTY1'));self.assertFalse(buffer)
if __name__=='__main__':unittest.main()
