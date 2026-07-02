# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    Makefile                                           :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: ssawa <ssawa@student.42tokyo.jp>           +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/05/27 13:15:00 by ssawa             #+#    #+#              #
#    Updated: 2026/06/18 10:15:05 by ssawa            ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

COMPOSE_FILE    = srcs/docker-compose.yml
ENV_FILE        = srcs/.env
COMPOSE         = docker compose --env-file $(ENV_FILE) -f $(COMPOSE_FILE)
SECRETS_DIR     = secrets
REQUIRED_ENV_VARS = \
	USER_LOGIN \
	DOMAIN_NAME \
	MYSQL_DATABASE \
	MYSQL_USER \
	WP_ADMIN_USER \
	WP_ADMIN_EMAIL \
	WP_USER \
	WP_USER_EMAIL
REQUIRED_SECRETS = \
	$(SECRETS_DIR)/db_password.txt \
	$(SECRETS_DIR)/db_root_password.txt \
	$(SECRETS_DIR)/wp_admin_password.txt \
	$(SECRETS_DIR)/wp_user_password.txt

ifneq (,$(wildcard $(ENV_FILE)))
include $(ENV_FILE)
endif

DATA_DIR       = /home/$(USER_LOGIN)/data

all: up

check-env:
	@test -f $(ENV_FILE) || { echo "Missing $(ENV_FILE). Copy srcs/.env.example and edit it."; exit 1; }
	@$(foreach var,$(REQUIRED_ENV_VARS), test -n "$($(var))" || { echo "Missing $(var) in $(ENV_FILE)."; exit 1; };)

check-secrets:
	@for file in $(REQUIRED_SECRETS); do \
		test -s $$file || { echo "Missing or empty $$file. See DEV_DOC.md."; exit 1; }; \
	done

check-config: check-env check-secrets

up: check-config
	mkdir -p $(DATA_DIR)/mariadb
	mkdir -p $(DATA_DIR)/wordpress
	USER_LOGIN=$(USER_LOGIN) $(COMPOSE) up -d --build

down: check-env
	USER_LOGIN=$(USER_LOGIN) $(COMPOSE) down

clean: down
	USER_LOGIN=$(USER_LOGIN) $(COMPOSE) down --rmi all --volumes

fclean: check-env clean
	sudo rm -rf $(DATA_DIR)/mariadb
	sudo rm -rf $(DATA_DIR)/wordpress

re: fclean up

logs: check-env
	$(COMPOSE) logs -f

ps: check-env
	$(COMPOSE) ps

config: check-config
	USER_LOGIN=$(USER_LOGIN) $(COMPOSE) config

.PHONY: all check-env check-secrets check-config up down clean fclean re logs ps config
