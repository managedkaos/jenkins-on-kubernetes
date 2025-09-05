VENV=~/Envs/jenkins-on-kubernetes

setup:
	$(VENV)/bin/pip install -r development-requirements.txt

lint:
	yamllint ./yaml-config
	yamllint ./helm-config

