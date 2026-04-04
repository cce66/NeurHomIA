#!/bin/bash

cd /opt/neurhomia/installer

# install dépendances si besoin
pip3 install -r requirements.txt

# lance backend
python3 backend.py
