import urllib.request
import json
import datetime
import random
import string
import time
import os
import sys

os.system("title WARP-PLUS-CLOUDFLARE By ALIILAPRO")
os.system('cls' if os.name == 'nt' else 'clear')
referrer = input("请输入WARP应用内的设备ID：")

def genString(stringLength):
	try:
		letters = string.ascii_letters + string.digits
		return ''.join(random.choice(letters) for i in range(stringLength))
	except Exception as error:
		print(error)		    
def digitString(stringLength):
	try:
		digit = string.digits
		return ''.join((random.choice(digit) for i in range(stringLength)))    
	except Exception as error:
		print(error)	
url = f'https://api.cloudflareclient.com/v0a{digitString(3)}/reg'
def run():
	try:
		install_id = genString(22)
		body = {"key": "{}=".format(genString(43)),
				"install_id": install_id,
				"fcm_token": "{}:APA91b{}".format(install_id, genString(134)),
				"referrer": referrer,
				"warp_enabled": False,
				"tos": datetime.datetime.now().isoformat()[:-3] + "+02:00",
				"type": "Android",
				"locale": "es_ES"}
		data = json.dumps(body).encode('utf8')
		headers = {'Content-Type': 'application/json; charset=UTF-8',
					'Host': 'api.cloudflareclient.com',
					'Connection': 'Keep-Alive',
					'Accept-Encoding': 'gzip',
					'User-Agent': 'okhttp/3.12.1'
					}
		req         = urllib.request.Request(url, data, headers)
		response    = urllib.request.urlopen(req)
		status_code = response.getcode()	
		return status_code
	except Exception as error:
		print(error)	

g = 0
b = 0
while True:
	result = run()
	if result == 200:
		g = g + 1
		os.system('cls' if os.name == 'nt' else 'clear')
		animation = ["[■□□□□□□□□□] 10%","[■■□□□□□□□□] 20%", "[■■■□□□□□□□] 30%", "[■■■■□□□□□□] 40%", "[■■■■■□□□□□] 50%", "[■■■■■■□□□□] 60%", "[■■■■■■■□□□] 70%", "[■■■■■■■■□□] 80%", "[■■■■■■■■■□] 90%", "[■■■■■■■■■■] 100%"] 
		for i in range(len(animation)):
			time.sleep(0.5)
			sys.stdout.write("\r[+] 准备中... " + animation[i % len(animation)])
			sys.stdout.flush()
		print(f"\n[-] 正在为 {referrer} 账户工作")    
		print(f"[:)] {g} GB流量已成功添加到你的账户！")
		print(f"[#] {g} 次成功 {b} 次失败")
		print("[*] 等待18秒，下一个请求准备发出")
		time.sleep(18)
	else:
		b = b + 1
		os.system('cls' if os.name == 'nt' else 'clear')
		print("[:(] 我们无法连接到CloudFlare服务器，请稍后重试")
		print(f"[#] {g} 次成功 {b} 次失败")
