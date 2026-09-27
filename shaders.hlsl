// Структура данных, которая передается от вершинного шейдера к пиксельному
struct VS_OUTPUT
{
    float4 Pos : SV_POSITION; // Позиция вершины на экране
    float2 Tex : TEXCOORD0;   // Текстурные координаты кадра
};

// Вершинный шейдер (просто передает геометрию экрана дальше)
VS_OUTPUT VS(float4 Pos : POSITION, float2 Tex : TEXCOORD)
{
    VS_OUTPUT output = (VS_OUTPUT)0;
    output.Pos = Pos;
    output.Tex = Tex;
    return output;
}

// Объявляем входную текстуру и сэмплер Point-фильтрации
Texture2D shaderTexture : register(t0);
SamplerState samplerState0 : register(s0);

// Буфер констант для приема физических параметров из C++ кода
cbuffer cbData : register(b0)
{
    float width;     // Ширина картинки (2.0)
    float height;    // Высота картинки (2.0)
    float d_width;   // Шаг пикселя по горизонтали (0.5)
    float d_height;  // Шаг пикселя по вертикали (0.5)
};

// Константа весов для перевода RGB в монохромную яркость (Luma)
static const float3 WEIGHT = float3(0.299f, 0.587f, 0.114f);

// Пиксельный шейдер: 3-й проход (Статистический анализ блоков 4х4)
float4 PS(VS_OUTPUT input) : SV_Target
{
    float GrayMid = 0.0f; // Средняя яркость блока
    float GrayMin = 1.0f; // Самый темный пиксель в блоке
    float GrayMax = 0.0f; // Самый яркий пиксель в блоке
    float GraySqr = 0.0f; // Дисперсия (среднеквадратичное отклонение / контраст)

    float2 tex_coord;

    // Первый проход по блоку 4х4: считаем сумму яркостей и ищем экстремумы
    [unroll]
    for (int i_width = -1; i_width < 3; i_width++)
    {
        for (int i_height = -1; i_height < 3; i_height++)
        {
            // Рассчитываем точную координату соседнего пикселя в блоке
            tex_coord.x = input.Tex.x + float(i_width) * d_width;
            tex_coord.y = input.Tex.y + float(i_height) * d_height;

            // Читаем чистый, неискаженный пиксель через Point-выборку
            float4 k1 = shaderTexture.Sample(samplerState0, tex_coord);
            float gray = dot(k1.rgb, WEIGHT);

            // Накапливаем сумму для среднего значения
            GrayMid += gray;

            // Фиксируем минимум и максимум
            if (gray < GrayMin) GrayMin = gray;
            if (gray > GrayMax) GrayMax = gray;
        }
    }

    // Находим среднее значение яркости по 16 точкам
    GrayMid /= 16.0f;

    // Второй проход по блоку 4х4: строго рассчитываем среднеквадратичное отклонение
    [unroll]
    for (int j_width = -1; j_width < 3; j_width++)
    {
        for (int j_height = -1; j_height < 3; j_height++)
        {
            tex_coord.x = input.Tex.x + float(j_width) * d_width;
            tex_coord.y = input.Tex.y + float(j_height) * d_height;

            float4 k1 = shaderTexture.Sample(samplerState0, tex_coord);
            float gray = dot(k1.rgb, WEIGHT);

            // Суммируем квадраты отклонений от найденного среднего
            GraySqr += (gray - GrayMid) * (gray - GrayMid);
        }
    }

    // Финальный расчет дисперсии (контрастности макроблока)
    GraySqr = sqrt(GraySqr / 16.0f);

    // Упаковываем техническую аналитику блока в RGBA каналы пикселя
    // R = Среднее, G = Минимум, B = Максимум, A = Контраст
    return float4(GrayMid, GrayMin, GrayMax, GraySqr);
}
