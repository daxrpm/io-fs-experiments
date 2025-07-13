# Makefile para el Proyecto de Experimentos de E/S
#
# Uso:
#   make          - Compila todos los ejecutables.
#   make all      - Compila todos los ejecutables (igual que make).
#   make clean    - Elimina todos los archivos compilados y ejecutables.
#   make [target] - Compila un ejecutable específico (ej. make file_buffered).

# Compilador y flags
CC = gcc
CFLAGS = -Wall -O2 -std=gnu99
LDFLAGS =

# Directorios
SRCDIR = src
BINDIR = bin

# Lista de fuentes y ejecutables
SOURCES = $(wildcard $(SRCDIR)/*.c)
TARGETS = \
    $(BINDIR)/file_buffered \
    $(BINDIR)/file_direct \
    $(BINDIR)/file_sendfile \
    $(BINDIR)/unix_socket_server \
    $(BINDIR)/unix_socket_client \
    $(BINDIR)/tcp_server \
    $(BINDIR)/tcp_client

# Regla por defecto: compilar todo
all: $(TARGETS)

# Regla para crear el directorio de binarios
$(BINDIR):
	mkdir -p $(BINDIR)

# Regla genérica para compilar un ejecutable desde su fuente
$(BINDIR)/%: $(SRCDIR)/%.c | $(BINDIR)
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS)

# Dependencias específicas (si las hubiera)
# Por ejemplo, si un programa necesitara una librería matemática:
# $(BINDIR)/mi_programa: LDFLAGS = -lm

# Regla para limpiar el proyecto
clean:
	@echo "Limpiando archivos compilados..."
	rm -rf $(BINDIR)

# Evita que 'clean' y 'all' se confundan con archivos de esos nombres
.PHONY: all clean 