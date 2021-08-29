
motor_control.exe: motor_control.c
	cl motor_control.c wsock32.lib

firewall:
	netsh advfirewall firewall add rule name="kohn" dir=in protocol=UDP localport=8000 action=Allow

uart:
	devcon /hwids =Ports
	bcdedit /set debug off

test:
	cat test.txt | nc -u 192.168.1.30 8000

