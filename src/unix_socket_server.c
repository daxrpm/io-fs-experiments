#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <errno.h>
#include <sys/socket.h>
#include <sys/un.h>

/**
 * unix_socket_server.c
 *
 * Servidor que recibe datos a través de un socket de dominio UNIX y los
 * escribe en un archivo.
 *
 * Referencia teórica: Stallings, Cap. 18 (Client-Server Computing) y
 * CS241 Coursebook, Sección 4.3.2. Los sockets de dominio UNIX son un
 * mecanismo de IPC que opera en una única máquina. Son gestionados por el
 * kernel y representados como un archivo en el sistema de ficheros. Se espera
 * que sean más rápidos que TCP/IP para comunicación local al evitar la
 * sobrecarga de la pila de red.
 *
 * Argumentos:
 *  - <socket_path>: Ruta del sistema de archivos para el socket.
 *  - <fichero_salida>: Ruta al archivo donde se guardarán los datos recibidos.
 *  - <tam_buffer>: Tamaño del búfer de recepción/escritura en bytes.
 */

#define MAX_PENDING_CONNECTIONS 1

void print_usage(const char *prog_name) {
    fprintf(stderr, "Uso: %s <socket_path> <fichero_salida> <tam_buffer>\n", prog_name);
}

int main(int argc, char *argv[]) {
    if (argc != 4) {
        print_usage(argv[0]);
        exit(EXIT_FAILURE);
    }

    const char *socket_path = argv[1];
    const char *output_path = argv[2];
    long buffer_size = atol(argv[3]);

    if (buffer_size <= 0) {
        fprintf(stderr, "Error: El tamaño del buffer debe ser un entero positivo.\n");
        exit(EXIT_FAILURE);
    }

    // --- Configuración del socket ---
    int server_sock, client_sock;
    struct sockaddr_un server_addr, client_addr;
    socklen_t client_addr_len = sizeof(client_addr);

    // Crear el socket
    server_sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_sock == -1) {
        perror("Error al crear el socket");
        exit(EXIT_FAILURE);
    }

    // Configurar la dirección del servidor y asegurarse de que el path no sea demasiado largo
    memset(&server_addr, 0, sizeof(struct sockaddr_un));
    server_addr.sun_family = AF_UNIX;
    strncpy(server_addr.sun_path, socket_path, sizeof(server_addr.sun_path) - 1);

    // Eliminar el archivo del socket si ya existe (de una ejecución anterior)
    unlink(socket_path);

    // Enlazar el socket a la dirección
    if (bind(server_sock, (struct sockaddr *)&server_addr, sizeof(struct sockaddr_un)) == -1) {
        perror("Error en bind");
        close(server_sock);
        exit(EXIT_FAILURE);
    }

    // Escuchar conexiones entrantes
    if (listen(server_sock, MAX_PENDING_CONNECTIONS) == -1) {
        perror("Error en listen");
        close(server_sock);
        exit(EXIT_FAILURE);
    }

    // printf("Servidor UNIX esperando conexión en %s\n", socket_path);

    // Aceptar una conexión (bloqueante)
    client_sock = accept(server_sock, (struct sockaddr *)&client_addr, &client_addr_len);
    if (client_sock == -1) {
        perror("Error en accept");
        close(server_sock);
        exit(EXIT_FAILURE);
    }

    // --- Abrir archivo de salida ---
    int fd_out = open(output_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd_out == -1) {
        perror("Error al abrir el archivo de salida");
        close(client_sock);
        close(server_sock);
        exit(EXIT_FAILURE);
    }

    // --- Asignar búfer y recibir datos ---
    char *buffer = malloc(buffer_size);
    if (buffer == NULL) {
        perror("Error al asignar memoria para el buffer");
        close(fd_out);
        close(client_sock);
        close(server_sock);
        exit(EXIT_FAILURE);
    }

    struct timespec start, end;
    long recv_calls = 0;
    long write_calls = 0;
    ssize_t bytes_received;

    clock_gettime(CLOCK_MONOTONIC, &start);

    while ((bytes_received = recv(client_sock, buffer, buffer_size, 0)) > 0) {
        recv_calls++;
        ssize_t bytes_written = write(fd_out, buffer, bytes_received);
        write_calls++;
        if (bytes_written != bytes_received) {
            perror("Error de escritura incompleta en el servidor");
            break; // Salir del bucle en caso de error
        }
    }

    if (bytes_received == -1) {
        perror("Error en recv del servidor");
    }

    clock_gettime(CLOCK_MONOTONIC, &end);
    double time_taken = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;
    
    // --- Limpieza ---
    free(buffer);
    close(fd_out);
    close(client_sock);
    close(server_sock);
    unlink(socket_path); // Eliminar el archivo del socket

    // --- Imprimir resultados para el parser ---
    printf("Mechanism: UNIX Socket Server\n");
    printf("BufferSize: %ld\n", buffer_size);
    printf("TimeTakenServer: %.6f\n", time_taken);
    printf("RecvCalls: %ld\n", recv_calls);
    printf("WriteCalls: %ld\n", write_calls);

    return 0;
} 