# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    Makefile                                           :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: ssawa <ssawa@student.42tokyo.jp>           +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/05/27 13:15:00 by ssawa             #+#    #+#              #
#    Updated: 2026/05/27 13:15:01 by ssawa            ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

up:
	docker-compose up -d

clean:
	docker-compose down

fclean:
	docker system prune -a
re:

.PHONY: up clean
