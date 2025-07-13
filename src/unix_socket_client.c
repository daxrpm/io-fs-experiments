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
 * unix_socket_client.c
 *
 * Cliente que lee un archivo local y lo envía a un servidor a través de un
 * socket de dominio UNIX.
 *
 * Referencia teórica: Complementa al servidor para demostrar el modelo
 * cliente-servidor para IPC local (Stallings, Cap. 18). Mide el rendimiento
 * desde la perspectiva del emisor.
 *
 * Argumentos:
 *  - <socket_path>: Ruta del sistema de archivos para el socket del servidor.
 *  - <fichero_entrada>: Ruta al archivo que se va a enviar.
 *  - <tam_buffer>: Tamaño del búfer de lectura/envío en bytes.
 */

void print_usage(const char *prog_name) {
    fprintf(stderr, "Uso: %s <socket_path> <fichero_entrada> <tam_buffer>\n", prog_name);
}

int main(int argc, char *argv[]) {
    if (argc != 4) {
        print_usage(argv[0]);
        exit(EXIT_FAILURE);
    }

    const char *socket_path = argv[1];
    const char *input_path = argv[2];
    long buffer_size = atol(argv[3]);

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
    struct sockaddr_un server_addr;

    client_sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (client_sock == -1) {
        perror("Error al crear el socket del cliente");
        close(fd_in);
        exit(EXIT_FAILURE);
    }

    memset(&server_addr, 0, sizeof(struct sockaddr_un));
    server_addr.sun_family = AF_UNIX;
    strncpy(server_addr.sun_path, socket_path, sizeof(server_addr.sun_path) - 1);

    // Conectarse al servidor
    if (connect(client_sock, (struct sockaddr *)&server_addr, sizeof(struct sockaddr_un)) == -1) {
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
            // Salir del bucle en caso de error
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
    close(client_sock); // Cierra la conexión, el servidor verá EOF (recv retorna 0)

    // --- Imprimir resultados para el parser ---
    printf("Mechanism: UNIX Socket Client\n");
    printf("BufferSize: %ld\n", buffer_size);
    printf("TimeTakenClient: %.6f\n", time_taken);
    printf("ReadCalls: %ld\n", read_calls);
    printf("SendCalls: %ld\n", send_calls);

    return 0;
} 