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
 * tcp_client.c
 *
 * Cliente que lee un archivo local y lo envía a un servidor a través de un
 * socket TCP/IP.
 *
 * Referencia teórica: Completa el par cliente-servidor para la comunicación
 * en red (Stallings, Cap. 18). El rendimiento medido aquí incluirá la
 * latencia de la red y la sobrecarga del protocolo TCP/IP.
 *
 * Argumentos:
 *  - <ip_servidor>: Dirección IP del servidor.
 *  - <puerto>: Puerto en el que el servidor está escuchando.
 *  - <fichero_entrada>: Ruta al archivo que se va a enviar.
 *  - <tam_buffer>: Tamaño del búfer de lectura/envío en bytes.
 */

void print_usage(const char *prog_name) {
    fprintf(stderr, "Uso: %s <ip_servidor> <puerto> <fichero_entrada> <tam_buffer>\n", prog_name);
}

int main(int argc, char *argv[]) {
    if (argc != 5) {
        print_usage(argv[0]);
        exit(EXIT_FAILURE);
    }

    const char *server_ip = argv[1];
    int port = atoi(argv[2]);
    const char *input_path = argv[3];
    long buffer_size = atol(argv[4]);

    if (port <= 0 || port > 65535) {
        fprintf(stderr, "Error: El puerto debe ser un número entre 1 y 65535.\n");
        exit(EXIT_FAILURE);
    }
    if (buffer_size <= 0) {
        fprintf(stderr, "Error: El tamaño del buffer debe ser un entero positivo.\n");
        exit(EXIT_FAILURE);
    }

    // --- Abrir archivo de entrada ---
    int fd_in = open(input_path, O_RDONLY);
    if (fd_in == -1) {
        perror("Error al abrir el archivo de entrada");
        exit(EXIT_FAILURE);
    }

    // --- Configuración del socket ---
    int client_sock;
    struct sockaddr_in server_addr;

    client_sock = socket(AF_INET, SOCK_STREAM, 0);
    if (client_sock == -1) {
        perror("Error al crear el socket del cliente");
        close(fd_in);
        exit(EXIT_FAILURE);
    }

    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(port);
    if (inet_pton(AF_INET, server_ip, &server_addr.sin_addr) <= 0) {
        perror("Dirección IP inválida o no soportada");
        close(fd_in);
        close(client_sock);
        exit(EXIT_FAILURE);
    }

    // Conectarse al servidor
    if (connect(client_sock, (struct sockaddr *)&server_addr, sizeof(server_addr)) == -1) {
        perror("Error al conectar con el servidor");
        close(fd_in);
        close(client_sock);
        exit(EXIT_FAILURE);
    }
    
    // --- Asignar búfer y enviar datos ---
    char *buffer = malloc(buffer_size);
    if (buffer == NULL) {
        perror("Error al asignar memoria para el buffer");
        close(fd_in);
        close(client_sock);
        exit(EXIT_FAILURE);
    }

    struct timespec start, end;
    long read_calls = 0;
    long send_calls = 0;
    ssize_t bytes_read;

    clock_gettime(CLOCK_MONOTONIC, &start);

    while ((bytes_read = read(fd_in, buffer, buffer_size)) > 0) {
        read_calls++;
        if (send(client_sock, buffer, bytes_read, 0) == -1) {
            perror("Error en send del cliente");
            break;
        }
        send_calls++;
    }

    if (bytes_read == -1) {
        perror("Error de lectura del archivo de entrada");
    }

    clock_gettime(CLOCK_MONOTONIC, &end);
    double time_taken = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;

    // --- Limpieza ---
    free(buffer);
    close(fd_in);
    close(client_sock);

    // --- Imprimir resultados ---
    printf("Mechanism: TCP Client\n");
    printf("BufferSize: %ld\n", buffer_size);
    printf("TimeTakenClient: %.6f\n", time_taken);
    printf("ReadCalls: %ld\n", read_calls);
    printf("SendCalls: %ld\n", send_calls);

    return 0;
} 