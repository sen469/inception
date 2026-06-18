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

COMPOSE_FILE	= srcs/docker-compose.yml
+DATA_DIR       = /home/$(shell whoami)/data

all: up

up:
	mkdir -p $(DATA_DIR)/mariadb
	mkdir -p $(DATA_DIR)/wordpress
	docker compose -f $(COMPOSE_FILE) up -d --build

down:
	docker compose -f $(COMPOSE_FILE) down

clean: down
	docker compose -f $(COMPOSE_FILE) down --rmi all --volumes

fclean: clean
	sudo rm -rf $(DATA_DIR)/mariadb
	sudo rm -rf $(DATA_DIR)/wordpress
	docker system prune -af

re: fclean up

logs:
	docker compose -f $(COMPOSE_FILE) logs -f

ps:
	docker compose -f $(COMPOSE_FILE) ps

.PHONY: all up down clean fclean re logs ps
