#!/usr/bin/env python
# encoding: utf-8

# Script para fazer á instalação do knock v4.1.0.
# knock Code By: https://github.com/guelfoweb/knock/
# Instalador By: Zwdeff @ZWDChannel ...............


import os
import sys

from os import *
from sys import *

print('Instalando. Knockpy. Aguarde ..')
system('sudo apt-get update 1> /dev/null 2> /dev/null')
system('sudo apt-get install python-dnspython 1> /dev/null 2> /dev/null')

if os.path.isfile('/usr/bin/git') == False:
   system('apt-get install git -y 1> /dev/null 2> /dev/null')
   
system('git clone https://github.com/guelfoweb/knock.git 1> /dev/null 2> /dev/null')
system('''echo '{
        "virustotal": "d09f456a31ee0acaed24a328680c71caa2057f88d67e109ba693ca115ff8509c"
       }' > knock/knockpy/config.json''')
              
system('cd knock && sudo python setup.py install 1> /dev/null 2> /dev/null')
print('Concluido. Knockpy 4.1 Instalado.')
print('usage: knockpy [-h] [-v] [-w WORDLIST] [-r] [-c] [-j] domain')
print('''example:
  knockpy domain.com
  knockpy domain.com -w wordlist.txt
  knockpy -r domain.com or IP
  knockpy -c domain.com
  knockpy -j domain.com''')