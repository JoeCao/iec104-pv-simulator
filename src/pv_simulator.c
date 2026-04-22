/*
 * 光伏发电站 IEC 60870-5-104 模拟器
 * 支持从 CSV 动态加载点位与仿真规则
 */

#include <stdlib.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <signal.h>
#include <math.h>
#include <time.h>

#include "cs104_slave.h"
#include "hal_thread.h"

#define SPONTANEOUS_INTERVAL 5
#define MAX_LINE_LEN 4096
#define MAX_FIELD_LEN 256

typedef enum {
    SIM_FIXED,
    SIM_RANDOM_UNIFORM,
    SIM_RANDOM_WALK,
    SIM_SOLAR_SCALED,
    SIM_DERIVED_FORMULA,
    SIM_STATUS_FROM_CONTROL,
    SIM_COUNTER
} SimClass;

typedef struct {
    int ioa;
    int ca;
    bool enabled;
    bool is_write;
    bool is_bit;
    TypeID type_id;

    char name[128];
    char identity[128];
    char formula[256];
    char depends_on[256];
    char control_ref[128];

    float value;
    float min_val;
    float max_val;
    float noise;
    float deadband;
    int update_ms;
    time_t last_update_time;

    float last_reported_value;
    bool last_reported_bit;
    time_t last_report_time;

    SimClass sim_class;
} SimPoint;

static bool running = true;
static CS104_Slave slave = NULL;
static SimPoint* points = NULL;
static int point_count = 0;
static int read_point_count = 0;
static int write_point_count = 0;

static void sigint_handler(int signalId)
{
    (void) signalId;
    running = false;
}

static float randf(float min_v, float max_v)
{
    if (max_v <= min_v)
        return min_v;
    return min_v + ((float) rand() / (float) RAND_MAX) * (max_v - min_v);
}

static float clampf(float v, float min_v, float max_v)
{
    if (v < min_v) return min_v;
    if (v > max_v) return max_v;
    return v;
}

static float get_solar_factor(void)
{
    time_t now = time(NULL);
    struct tm* tm_info = localtime(&now);
    float hour = tm_info->tm_hour + tm_info->tm_min / 60.0f;

    if (hour < 6 || hour > 18)
        return 0.0f;

    float solar_angle = (hour - 6) / 12.0f * (float) M_PI;
    float base_factor = sinf(solar_angle);
    float cloud_factor = 1.0f + randf(-0.15f, 0.15f);
    float result = base_factor * cloud_factor;

    return result > 0 ? result : 0;
}

static SimPoint* find_point_by_identity(const char* identity)
{
    for (int i = 0; i < point_count; i++) {
        if (strcmp(points[i].identity, identity) == 0)
            return &points[i];
    }
    return NULL;
}

static SimPoint* find_point_by_ioa_type(int ioa, TypeID type_id)
{
    for (int i = 0; i < point_count; i++) {
        if (points[i].ioa == ioa && points[i].type_id == type_id && points[i].enabled)
            return &points[i];
    }
    return NULL;
}

static int parse_address(const char* address, int* ca, TypeID* type_id, int* ioa)
{
    int local_ca = 0;
    int local_ioa = 0;
    char type_buf[32] = {0};

    if (sscanf(address, "%d!%31[^!]!%d", &local_ca, type_buf, &local_ioa) != 3)
        return -1;

    TypeID t;
    if (strcmp(type_buf, "M_ME_NC") == 0) t = M_ME_NC_1;
    else if (strcmp(type_buf, "M_SP_NA") == 0) t = M_SP_NA_1;
    else if (strcmp(type_buf, "C_SC_NA") == 0) t = C_SC_NA_1;
    else return -1;

    *ca = local_ca;
    *ioa = local_ioa;
    *type_id = t;
    return 0;
}

static SimClass parse_sim_class(const char* s)
{
    if (strcmp(s, "fixed") == 0) return SIM_FIXED;
    if (strcmp(s, "random_uniform") == 0) return SIM_RANDOM_UNIFORM;
    if (strcmp(s, "random_walk") == 0) return SIM_RANDOM_WALK;
    if (strcmp(s, "solar_scaled") == 0) return SIM_SOLAR_SCALED;
    if (strcmp(s, "derived_formula") == 0) return SIM_DERIVED_FORMULA;
    if (strcmp(s, "status_from_control") == 0) return SIM_STATUS_FROM_CONTROL;
    if (strcmp(s, "counter") == 0) return SIM_COUNTER;
    return SIM_RANDOM_WALK;
}

static char* trim(char* s)
{
    while (*s == ' ' || *s == '\t' || *s == '\r' || *s == '\n') s++;
    if (*s == '\0') return s;
    char* end = s + strlen(s) - 1;
    while (end > s && (*end == ' ' || *end == '\t' || *end == '\r' || *end == '\n')) {
        *end = '\0';
        end--;
    }
    return s;
}

static int split_csv_line(char* line, char fields[][MAX_FIELD_LEN], int max_fields)
{
    int count = 0;
    int start = 0;
    int len = (int) strlen(line);

    for (int i = 0; i <= len && count < max_fields; i++) {
        if (line[i] == ',' || line[i] == '\0' || line[i] == '\n' || line[i] == '\r') {
            int field_len = i - start;
            if (field_len < 0) field_len = 0;
            if (field_len >= MAX_FIELD_LEN) field_len = MAX_FIELD_LEN - 1;

            memcpy(fields[count], &line[start], (size_t) field_len);
            fields[count][field_len] = '\0';

            char* t = trim(fields[count]);
            if (t != fields[count]) {
                memmove(fields[count], t, strlen(t) + 1);
            }

            count++;
            start = i + 1;
        }
    }

    return count;
}

static int load_points_from_csv(const char* path)
{
    FILE* fp = fopen(path, "r");
    if (fp == NULL) {
        printf("无法打开配置文件: %s\n", path);
        return -1;
    }

    char line[MAX_LINE_LEN];
    int capacity = 1024;
    points = (SimPoint*) calloc((size_t) capacity, sizeof(SimPoint));
    if (points == NULL) {
        fclose(fp);
        return -1;
    }

    // Skip header
    if (fgets(line, sizeof(line), fp) == NULL) {
        fclose(fp);
        return -1;
    }

    while (fgets(line, sizeof(line), fp) != NULL) {
        char tmp[MAX_LINE_LEN];
        char fields[32][MAX_FIELD_LEN];
        strncpy(tmp, line, sizeof(tmp) - 1);
        tmp[sizeof(tmp) - 1] = '\0';

        int n = split_csv_line(tmp, fields, 32);
        if (n < 22)
            continue;

        if (point_count >= capacity) {
            capacity *= 2;
            SimPoint* new_points = (SimPoint*) realloc(points, (size_t) capacity * sizeof(SimPoint));
            if (new_points == NULL) {
                fclose(fp);
                return -1;
            }
            points = new_points;
        }

        SimPoint* p = &points[point_count];
        memset(p, 0, sizeof(SimPoint));

        strncpy(p->name, fields[2], sizeof(p->name) - 1);
        strncpy(p->identity, fields[10], sizeof(p->identity) - 1);
        strncpy(p->formula, fields[17], sizeof(p->formula) - 1);
        strncpy(p->depends_on, fields[18], sizeof(p->depends_on) - 1);
        strncpy(p->control_ref, fields[20], sizeof(p->control_ref) - 1);

        if (parse_address(fields[3], &p->ca, &p->type_id, &p->ioa) != 0)
            continue;

        p->is_write = (strcmp(fields[4], "Write") == 0);
        p->is_bit = (strcmp(fields[5], "BIT") == 0);
        p->sim_class = parse_sim_class(fields[11]);
        p->enabled = (strcmp(fields[21], "0") != 0);

        p->min_val = (fields[12][0] == '\0') ? 0.0f : strtof(fields[12], NULL);
        p->max_val = (fields[13][0] == '\0') ? 0.0f : strtof(fields[13], NULL);
        p->noise = (fields[14][0] == '\0') ? 0.0f : strtof(fields[14], NULL);
        p->deadband = (fields[15][0] == '\0') ? 1.0f : strtof(fields[15], NULL);
        p->update_ms = (fields[16][0] == '\0') ? 1000 : atoi(fields[16]);
        p->value = (fields[19][0] == '\0') ? 0.0f : strtof(fields[19], NULL);
        p->last_reported_value = p->value;
        p->last_reported_bit = (p->value > 0.5f);
        p->last_report_time = 0;
        p->last_update_time = 0;

        if (p->enabled) {
            if (p->is_write) write_point_count++;
            else read_point_count++;
        }

        point_count++;
    }

    fclose(fp);
    return point_count;
}

static void send_spontaneous_float(SimPoint* p)
{
    if (slave == NULL) return;
    CS101_AppLayerParameters alParams = CS104_Slave_getAppLayerParameters(slave);
    CS101_ASDU asdu = CS101_ASDU_create(alParams, false, CS101_COT_SPONTANEOUS, 0, p->ca, false, false);
    InformationObject io = (InformationObject) MeasuredValueShort_create(NULL, p->ioa, p->value, IEC60870_QUALITY_GOOD);
    CS101_ASDU_addInformationObject(asdu, io);
    InformationObject_destroy(io);
    CS104_Slave_enqueueASDU(slave, asdu);
    CS101_ASDU_destroy(asdu);
    p->last_reported_value = p->value;
    p->last_report_time = time(NULL);
}

static void send_spontaneous_bit(SimPoint* p)
{
    if (slave == NULL) return;
    bool bit_val = (p->value > 0.5f);
    CS101_AppLayerParameters alParams = CS104_Slave_getAppLayerParameters(slave);
    CS101_ASDU asdu = CS101_ASDU_create(alParams, false, CS101_COT_SPONTANEOUS, 0, p->ca, false, false);
    InformationObject io = (InformationObject) SinglePointInformation_create(NULL, p->ioa, bit_val, IEC60870_QUALITY_GOOD);
    CS101_ASDU_addInformationObject(asdu, io);
    InformationObject_destroy(io);
    CS104_Slave_enqueueASDU(slave, asdu);
    CS101_ASDU_destroy(asdu);
    p->last_reported_bit = bit_val;
    p->last_report_time = time(NULL);
}

static float eval_formula_simple(const char* formula)
{
    char a[128] = {0};
    char b[128] = {0};
    float c = 0.0f;

    // identityA*identityB/const
    if (sscanf(formula, "%127[^*]*%127[^/]/%f", a, b, &c) == 3 && c != 0.0f) {
        SimPoint* pa = find_point_by_identity(trim(a));
        SimPoint* pb = find_point_by_identity(trim(b));
        if (pa != NULL && pb != NULL) {
            return pa->value * pb->value / c;
        }
    }

    // identityA*const
    if (sscanf(formula, "%127[^*]*%f", a, &c) == 2) {
        SimPoint* pa = find_point_by_identity(trim(a));
        if (pa != NULL) {
            return pa->value * c;
        }
    }

    return 0.0f;
}

static void update_point_value(SimPoint* p, float solar_factor)
{
    if (!p->enabled || p->is_write)
        return;

    time_t now = time(NULL);
    if ((now - p->last_update_time) * 1000 < p->update_ms)
        return;
    p->last_update_time = now;

    switch (p->sim_class) {
        case SIM_FIXED:
            break;
        case SIM_RANDOM_UNIFORM:
            p->value = randf(p->min_val, p->max_val);
            break;
        case SIM_RANDOM_WALK:
            if (p->max_val > p->min_val) {
                float step = randf(-p->noise, p->noise);
                p->value = clampf(p->value + step, p->min_val, p->max_val);
            }
            break;
        case SIM_SOLAR_SCALED: {
            float base = p->min_val + (p->max_val - p->min_val) * solar_factor;
            p->value = clampf(base + randf(-p->noise, p->noise), p->min_val, p->max_val);
            break;
        }
        case SIM_DERIVED_FORMULA:
            p->value = eval_formula_simple(p->formula);
            break;
        case SIM_STATUS_FROM_CONTROL: {
            SimPoint* ctrl = find_point_by_identity(p->control_ref);
            p->value = (ctrl != NULL && ctrl->value > 0.5f) ? 1.0f : 0.0f;
            break;
        }
        case SIM_COUNTER: {
            float inc = fabsf(p->noise) + randf(0.0f, fabsf(p->noise));
            p->value += inc;
            break;
        }
    }
}

static void update_all_points(void)
{
    float solar_factor = get_solar_factor();
    for (int i = 0; i < point_count; i++) {
        update_point_value(&points[i], solar_factor);
    }
}

static void check_and_send_changes(void)
{
    time_t now = time(NULL);
    for (int i = 0; i < point_count; i++) {
        SimPoint* p = &points[i];
        if (!p->enabled || p->is_write)
            continue;
        if ((now - p->last_report_time) < SPONTANEOUS_INTERVAL)
            continue;

        if (p->is_bit) {
            bool bit_val = (p->value > 0.5f);
            if (bit_val != p->last_reported_bit) {
                send_spontaneous_bit(p);
            }
        }
        else {
            float change = fabsf(p->value - p->last_reported_value);
            float threshold = (p->deadband > 0) ? p->deadband : 1.0f;
            if (change >= threshold) {
                send_spontaneous_float(p);
            }
        }
    }
}

static void send_gi_by_type(IMasterConnection connection, CS101_AppLayerParameters alParams, TypeID type_id)
{
    CS101_ASDU asdu = CS101_ASDU_create(alParams, false, CS101_COT_INTERROGATED_BY_STATION, 0, 1, false, false);
    for (int i = 0; i < point_count; i++) {
        SimPoint* p = &points[i];
        if (!p->enabled || p->is_write || p->type_id != type_id)
            continue;

        InformationObject io;
        if (type_id == M_ME_NC_1)
            io = (InformationObject) MeasuredValueShort_create(NULL, p->ioa, p->value, IEC60870_QUALITY_GOOD);
        else
            io = (InformationObject) SinglePointInformation_create(NULL, p->ioa, p->value > 0.5f, IEC60870_QUALITY_GOOD);

        CS101_ASDU_addInformationObject(asdu, io);
        InformationObject_destroy(io);

        if (CS101_ASDU_getNumberOfElements(asdu) >= 20) {
            IMasterConnection_sendASDU(connection, asdu);
            CS101_ASDU_destroy(asdu);
            asdu = CS101_ASDU_create(alParams, false, CS101_COT_INTERROGATED_BY_STATION, 0, 1, false, false);
        }
    }

    if (CS101_ASDU_getNumberOfElements(asdu) > 0)
        IMasterConnection_sendASDU(connection, asdu);
    CS101_ASDU_destroy(asdu);
}

static bool interrogationHandler(void* parameter, IMasterConnection connection, CS101_ASDU asdu, uint8_t qoi)
{
    (void) parameter;
    if (qoi != 20)
        return true;

    IMasterConnection_sendACT_CON(connection, asdu, false);
    CS101_AppLayerParameters alParams = IMasterConnection_getApplicationLayerParameters(connection);
    send_gi_by_type(connection, alParams, M_ME_NC_1);
    send_gi_by_type(connection, alParams, M_SP_NA_1);
    IMasterConnection_sendACT_TERM(connection, asdu);
    return true;
}

static bool asduHandler(void* parameter, IMasterConnection connection, CS101_ASDU asdu)
{
    (void) parameter;
    if (CS101_ASDU_getTypeID(asdu) != C_SC_NA_1)
        return false;

    InformationObject io = CS101_ASDU_getElement(asdu, 0);
    int ioa = InformationObject_getObjectAddress(io);
    SingleCommand sc = (SingleCommand) io;
    bool cmd_state = SingleCommand_getState(sc);

    SimPoint* ctrl = find_point_by_ioa_type(ioa, C_SC_NA_1);
    if (ctrl != NULL && ctrl->enabled && ctrl->is_write) {
        ctrl->value = cmd_state ? 1.0f : 0.0f;

        for (int i = 0; i < point_count; i++) {
            SimPoint* p = &points[i];
            if (p->enabled && p->sim_class == SIM_STATUS_FROM_CONTROL &&
                strcmp(p->control_ref, ctrl->identity) == 0) {
                p->value = ctrl->value;
                send_spontaneous_bit(p);
            }
        }
    }

    IMasterConnection_sendACT_CON(connection, asdu, false);
    InformationObject_destroy(io);
    return true;
}

static bool connectionRequestHandler(void* parameter, const char* ipAddress)
{
    (void) parameter;
    printf("[连接] 客户端连接请求: %s\n", ipAddress);
    return true;
}

static void connectionEventHandler(void* parameter, IMasterConnection con, CS104_PeerConnectionEvent event)
{
    (void) parameter;
    (void) con;
    if (event == CS104_CON_EVENT_CONNECTION_OPENED) printf("[连接] 客户端已连接\n");
    else if (event == CS104_CON_EVENT_CONNECTION_CLOSED) printf("[连接] 客户端已断开\n");
    else if (event == CS104_CON_EVENT_ACTIVATED) printf("[连接] 连接已激活 (STARTDT)\n");
    else if (event == CS104_CON_EVENT_DEACTIVATED) printf("[连接] 连接已停用 (STOPDT)\n");
}

int main(int argc, char** argv)
{
    const char* csv_path = "config/sim_rules.csv";
    int local_port = 2404;

    if (argc >= 2)
        csv_path = argv[1];
    if (argc >= 3) {
        local_port = atoi(argv[2]);
        if (local_port <= 0 || local_port > 65535) {
            printf("无效端口: %s\n", argv[2]);
            printf("用法: ./pv_simulator [csv_path] [port]\n");
            return 1;
        }
    }

    srand((unsigned int) time(NULL));
    signal(SIGINT, sigint_handler);

    printf("======================================================================\n");
    printf("      IEC 60870-5-104 动态点位模拟器 (CSV)\n");
    printf("======================================================================\n");

    if (load_points_from_csv(csv_path) <= 0) {
        printf("加载点位失败: %s\n", csv_path);
        return 1;
    }

    printf("已加载点位: %d (读=%d, 写=%d)\n", point_count, read_point_count, write_point_count);
    printf("配置文件: %s\n\n", csv_path);

    slave = CS104_Slave_create(10, 10);
    CS104_Slave_setLocalAddress(slave, "0.0.0.0");
    CS104_Slave_setLocalPort(slave, local_port);
    CS104_Slave_setInterrogationHandler(slave, interrogationHandler, NULL);
    CS104_Slave_setASDUHandler(slave, asduHandler, NULL);
    CS104_Slave_setConnectionRequestHandler(slave, connectionRequestHandler, NULL);
    CS104_Slave_setConnectionEventHandler(slave, connectionEventHandler, NULL);

    CS104_Slave_start(slave);
    if (CS104_Slave_isRunning(slave) == false) {
        printf("启动服务器失败! (port=%d)\n", local_port);
        printf("可能原因: 端口被占用。可执行: lsof -nP -iTCP:%d -sTCP:LISTEN\n", local_port);
        printf("也可换端口启动: ./pv_simulator %s 2504\n", csv_path);
        CS104_Slave_destroy(slave);
        free(points);
        return 1;
    }

    printf("服务器启动成功: 0.0.0.0:%d, CA=1\n", local_port);
    printf("运行中... 按 Ctrl+C 停止\n");

    int counter = 0;
    while (running) {
        Thread_sleep(1000);
        update_all_points();
        check_and_send_changes();

        if (++counter >= 10) {
            counter = 0;
            printf("[状态] 总点数=%d 读点=%d 写点=%d\n", point_count, read_point_count, write_point_count);
        }
    }

    printf("正在停止服务器...\n");
    CS104_Slave_stop(slave);
    CS104_Slave_destroy(slave);
    free(points);
    printf("程序退出\n");
    return 0;
}
