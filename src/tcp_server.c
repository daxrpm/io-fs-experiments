#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <errno.h>
#include <sys/socket.h>
#include <arpa/inet.h>

/**
 * tcp_server.c
 *
 * Servidor que recibe datos a través de un socket TCP/IP y los escribe
 * en un archivo.
 *
 * Referencia teórica: Stallings, Cap. 18 (Client-Server Computing). Este es
 * el modelo estándar de comunicación en red. A diferencia de los sockets UNIX,
 * TCP/IP incurre en la sobrecarga de la pila de red (TCP handshakes,
 * checksums, control de congestión, etc.), lo que se espera que lo haga más
 * lento para comunicación en la misma máquina, pero es necesario para la
 * comunicación entre máquinas distintas.
 *
 * Argumentos:
 *  - <puerto>: Puerto en el que el servidor escuchará.
 *  - <fichero_salida>: Ruta al archivo donde se guardarán los datos recibidos.
 *  - <tam_buffer>: Tamaño del búfer de recepción/escritura en bytes.
 */

#define MAX_PENDING_CONNECTIONS 5

void print_usage(const char *prog_name) {
    fprintf(stderr, "Uso: %s <puerto> <fichero_salida> <tam_buffer>\n", prog_name);
}

int main(int argc, char *argv[]) {
    if (argc != 4) {
        print_usage(argv[0]);
        exit(EXIT_FAILURE);
    }

    int port = atoi(argv[1]);
    const char *output_path = argv[2];
    long buffer_size = atol(argv[3]);

    if (port <= 0 || port > 65535) {
        fprintf(stderr, "Error: El puerto debe ser un número entre 1 y 65535.\n");
        exit(EXIT_FAILURE);
    }
    if (buffer_size <= 0) {
        fprintf(stderr, "Error: El tamaño del buffer debe ser un entero positivo.\n");
        exit(EXIT_FAILURE);
    }

    // --- Configuración del socket ---
    int server_sock, client_sock;
    struct sockaddr_in server_addr, client_addr;
    socklen_t client_addr_len = sizeof(client_addr);

    server_sock = socket(AF_INET, SOCK_STREAM, 0);
    if (server_sock == -1) {
        perror("Error al crear el socket");
        exit(EXIT_FAILURE);
    }

    // Permite reutilizar el puerto inmediatamente después de cerrar el servidor
    int opt = 1;
    if (setsockopt(server_sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt)) < 0) {
        perror("setsockopt(SO_REUSEADDR) failed");
    }

    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = htonl(INADDR_ANY); // Escuchar en todas las interfaces
    server_addr.sin_port = htons(port);

    if (bind(server_sock, (struct sockaddr *)&server_addr, sizeof(server_addr)) == -1) {
        perror("Error en bind");
        close(server_sock);
        exit(EXIT_FAILURE);
    }

    if (listen(server_sock, MAX_PENDING_CONNECTIONS) == -1) {
        perror("Error en listen");
        close(server_sock);
        exit(EXIT_FAILURE);
    }
    
    // printf("Servidor TCP esperando conexión en el puerto %d\n", port);

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
    
    // --- Recibir datos ---
    char *buffer = malloc(buffer_size);
    if (!buffer) {
        perror("malloc");
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
            break;
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

    // --- Imprimir resultados ---
    printf("Mechanism: TCP Server\n");
    printf("BufferSize: %ld\n", buffer_size);
    printf("TimeTakenServer: %.6f\n", time_taken);
    printf("RecvCalls: %ld\n", recv_calls);
    printf("WriteCalls: %ld\n", write_calls);

    return 0;
} 