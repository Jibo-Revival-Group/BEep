"""Stand-in for a modded Jibo's SSH server: root/jibo, Ed25519 host key, runs BEep's command.

Jibo keeps PM's state in /run, which macOS doesn't have; this maps it to a temp folder.
usage: python3 ci/fake-jibo-ssh.py <port> <run dir>
"""
import asyncio, sys
import asyncssh

PORT, RUN = int(sys.argv[1]), sys.argv[2]


class Robot(asyncssh.SSHServer):
    def begin_auth(self, username): return True
    def password_auth_supported(self): return True
    def validate_password(self, username, password): return username == 'root' and password == 'jibo'


async def run(process):
    command = process.command.replace('/run/', RUN + '/')
    with open(RUN + '/commands.log', 'a') as log: log.write(process.command + '\n')
    shell = await asyncio.create_subprocess_shell(command, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT)
    try:
        async for line in shell.stdout:
            process.stdout.write(line.decode())
    except Exception:
        pass
    finally:
        if shell.returncode is None: shell.kill()
        process.exit(0)


async def main():
    await asyncssh.create_server(Robot, '0.0.0.0', PORT, server_host_keys=[asyncssh.generate_private_key('ssh-ed25519'), asyncssh.generate_private_key('ecdsa-sha2-nistp256')], process_factory=run)
    print('fake Jibo SSH on', PORT, flush=True)
    await asyncio.Future()

asyncio.run(main())
