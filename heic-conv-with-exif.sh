#!/bin/bash
# этот скрипт обрабатывает файлы из резервной копии GooglePhoto
# и пытается восстановить отсутствующие данные exif в самом файле
# из прилагаемого к нему файла json


# вспомогательная функция, возвращает номер позиции С КОНЦА искомой подстроки в исходной строке
#   $1 - исходная строка
#   $2 - искомая подстрока
strindex() {
  x="${1##*"$2"}"
  [[ "$x" = "$1" ]] && echo -1 || echo "${#x}"
}



# временные файлы
tmp_jpg_file="/dev/shm/tmp-heic-conv-with-exif.jpg"
tmp_dir="/dev/shm/"

date_time_start=$( date +%s )
creator_work_email="eponim@mail.ru"
creator_work_url="https://www.postogram.org"
magic_quality_persent=87

path="$1"
path_length="${#path}"
dest_path="$2"
cnt_dir=0
cnt_files=0
k=0
new_dir=1
loop_folder_recurse() {
    for i in "$1"/*;do
        if [ -d "$i" ];then
            echo "dir:" "${i:path_length}"
            if ! [ -d "$dest_path${i:path_length}" ];then
               echo "$dest_path${i:path_length}"
               mkdir "$dest_path${i:path_length}"
               new_dir=1
            fi
            cnt_dir=$((cnt_dir+1))
            loop_folder_recurse "$i"
        elif [ -f "$i" ] && ( [ "${i##*.}" = "HEIC" ] || [ "${i##*.}" = "heic" ] \
                           || [ "${i##*.}" = "jpg" ] || [ "${i##*.}" = "JPG" ] \
                           || [ "${i##*.}" = "mov" ] || [ "${i##*.}" = "MOV" ] \
                           || [ "${i##*.}" = "mp4" ] || [ "${i##*.}" = "MP4" ] );then

           if [ new_dir = 1 ];then
              new_dir=0
           fi

           # проверим, есть ли JSON файл к текущему файлу
           json_file_name="${i}.json"
           if [ -f "$json_file_name" ];then
              echo "$json_file_name"
           else
              # проверяем имя файла на номер дубликата в скобках перед расширением , потому что (например):
              # IMG_1173(1).HEIC -> IMG_1173.HEIC(1).json !!!
              b1_pos=$( strindex "$i" "(" )
              b2_pos=$( strindex "$i" ")" )
              json_file_name="${i:0:${#i}-b1_pos-1}"."${i##*.}""${i:${#i}-b1_pos-1:b1_pos-b2_pos+1}".json
              if [ -f "$json_file_name" ];then
                 echo "$json_file_name"
              else
                 json_file_name=""
                 echo "$i" - JSON file not found...
              fi
           fi

           # заберём из JSON файла дату/время съёмки и GPS координаты
           if [ -f "$json_file_name" ];then
              j_dt=$( jq '.photoTakenTime .timestamp' "$json_file_name" )
              j_lt=$( jq '.geoDataExif .latitude' "$json_file_name" )
              j_lg=$( jq '.geoDataExif .longitude' "$json_file_name" )
              j_al=$( jq '.geoDataExif .altitude' "$json_file_name" )
           fi

           # очистим временный файл
           if [ -f "$tmp_jpg_file" ];then
              rm "$tmp_jpg_file"
           fi
           no_date=0 #если у файла нет даты съёмки, то стоавим 1

           # сформируем имя выходного файла
           jpg_file_name="$dest_path${i:path_length}"

           # HEIC конвертируем в JPG и копируем в tmp_jpg_file, остальные просто копируем в tmp_jpg_file
           if ( [ "${i##*.}" = "HEIC" ] || [ "${i##*.}" = "heic" ] );then
              jpg_file_name="${jpg_file_name::-4}jpg" # заменим расширение HEIC на JPG
              magick "$i" -quality "$magic_quality_persent" "$tmp_jpg_file" # конвертируем с заданным качеством
           else
              cp "$i" "$tmp_jpg_file"
           fi




#           if ( [ "${i##*.}" = "HEIC" ] || [ "${i##*.}" = "heic" ] );then
#              # конвертируем HEIC в JPG
#              jpg_file_name="$dest_path${i:path_length}"
#              jpg_file_name="${jpg_file_name::-4}jpg"
#              if ! [ -f "$jpg_file_name" ];then
#                 magick "$i" -quality "$magic_quality_persent" "$jpg_file_name"
#                 exiftool -DateTimeOriginal "$jpg_file_name"
#                 echo "$jpg_file_name"
#              fi
#           else 
#              if ! [ -f "$dest_path${i:path_length}" ];then
#                 # cp "$i" "$dest_path${i:path_length}"
#                 echo "$i" "$dest_path${i:path_length}"
#              fi
#           fi

           f_dt=$( exiftool -fast -DateTimeOriginal -n "$tmp_jpg_file" )
           f_lt=$( exiftool -fast -GPSLatitude -n "$tmp_jpg_file" )
           f_lg=$( exiftool -fast -GPSLongitude -n "$tmp_jpg_file" )
           f_al=$( exiftool -fast -GPSAltitude -n "$tmp_jpg_file" )

#           exiftool -DateTimeOriginal -GPSLatitude -GPSLongitude -GPSAltitude -n "$tmp_jpg_file" > "$tmp_exif_data$k.txt"
           echo -e "DateTimeOriginal: ${f_dt#*:}, ${#f_dt}, "$( date --date="@${j_dt//\"/}" +"%F %T")
           if ( [ ${#f_dt} = 0 ] );then
              no_date=1
              if ( [ ${#j_dt} > 0 ] );then
                 exiftool -DateTimeOriginal="$( date --date="@${j_dt//\"/}" +"%F %T")" "$tmp_jpg_file"
                 touch -mad $( date --date="@${j_dt//\"/}" +"%F %T") "$tmp_jpg_file"
                 no_date=0
              fi
           else
              dt="${f_dt#*: }"
              date1="${dt% *}"
              date2="${date1//:/-}"
              time1="${dt#* }"
              date_touch=$( echo "$date2" "$time1" )
              touch -mad "$date_touch" "$tmp_jpg_file"
           fi

           echo -e "GPSLatitude:      $f_lt, ${#f_lt}, $j_lt"
           echo -e "GPSLongitude:     $f_lg, ${#f_lg}, $j_lg"
           echo -e "GPSAltitude:      $f_al, ${#f_al}, $j_al\n"
#           echo -e $( date --date="@${j_dt//\"/}" )"\n"

#           if ! [ -f "$dest_path${i:path_length}" ];then
              cp -v -f --preserve=all "$tmp_jpg_file" "$jpg_file_name"
              echo "Скопирован:" "$dest_path${i:path_length}"
#           fi

           cnt_files=$((cnt_files+1))
        fi
    done
}

#jq '.photoTakenTime .timestamp' "/mnt/raid1/_public/GooglePhoto/test/IMG_1908.JPG.json"
#exiftool -DateTimeOriginal="$(date -d @1492627832 +%Y:%m:%d\ %T)" "/mnt/raid1/_public/GooglePhoto/test/IMG_1908.JPG"

#echo "Base path: $path"
loop_folder_recurse "$path"
execution_time=$( date +%s )
execution_time=$(( $execution_time-$date_time_start ))
echo "Proseed: dir=$cnt_dir, files=$cnt_files, time="$( date --date="@$execution_time" +"%T" )
