-- Restore the stock Docker view without replacing a firmware controller.
module('luci.controller.api.routerdocker168', package.seeall)

function index()
    local page = entry({'web','prosetting','docker'}, template('web/setting/docker'), 'DOCKER', 65)
    page.sysauth = 'admin'
    page.sysauth_authenticator = 'htmlauth'
    page.mediaurlbase = '/xiaoqiang/web'
    local root = node('api','routerdocker168')
    root.sysauth = 'admin'
    root.sysauth_authenticator = 'jsonauth'
    root.index = true
    entry({'api','routerdocker168','get_docker_info'}, call('getDockerInfo'), '', 1).leaf = true
    entry({'api','routerdocker168','set_mi_docker'}, call('setMiDocker'), '', 2).leaf = true
    entry({'api','routerdocker168','set_mi_docker_environment'}, call('setEnvironment'), '', 3).leaf = true
    entry({'api','routerdocker168','set_portainer_environment'}, call('setPortainer'), '', 4).leaf = true
end

local function launch(action)
    local http = require 'luci.http'
    if http.getenv('REQUEST_METHOD') ~= 'POST' then
        http.status(405, 'Method Not Allowed')
        http.write_json({code=1, msg='请使用 POST 请求。'})
        return
    end
    local mode = http.formvalue('mode')
    if mode ~= '0' and mode ~= '1' then
        http.write_json({code=1, msg='mode 必须为 0 或 1。'})
        return
    end
    local jobs = {switch={['0']='off',['1']='on'}, install={['0']='uninstall',['1']='install'}, portainer={['1']='portainer'}}
    local command = jobs[action][mode]
    if not command then http.write_json({code=1,msg='不支持此操作。'}); return end
    local uci = require('luci.model.uci').cursor()
    if command == 'portainer' then
        local image = uci:get('mi_docker','settings','portainer_image') or ''
        local digest = image:match('^portainer/portainer%-ce@sha256:([a-f0-9]+)$')
        if not digest or #digest ~= 64 then
            http.write_json({code=1,msg='请先通过 SSH 按部署说明配置已核对的 Portainer ARM64 镜像摘要。'})
            return
        end
    end
    -- Only constants reach the shell. Stock session/stok authentication is kept.
    local prefix = action == 'switch' and 'timeout -t 280 ' or ''
    local suffix = action == 'switch' and '' or ' &'
    local result = require('luci.sys').call(prefix..'/bin/sh /data/router-docker-1.0.168/runtime/control.sh '..command..' </dev/null >/tmp/router-docker168-job.log 2>&1'..suffix)
    http.write_json({code=result == 0 and 0 or 1, msg=result == 0 and '' or '操作失败，请通过SSH查看部署日志。'})
end
function setMiDocker() launch('switch') end
function setEnvironment() launch('install') end
function setPortainer() launch('portainer') end

function getDockerInfo()
    local uci = require('luci.model.uci').cursor()
    local fs = require 'nixio.fs'
    local function get(key) return uci:get('mi_docker','settings',key) or '0' end
    local installed = get('docker_install')
    local running = require('luci.sys').call('test -S /var/run/docker.sock && pidof dockerd >/dev/null 2>&1') == 0
    local result = {
        code=0, docker=get('docker_enable'), install_docker=installed,
        install_docker_success=installed, portainer=get('portainer_install'),
        disk_type='ext4 (UUID '..get('disk_uuid')..')', disk_size='外接存储',
        running=running and 1 or 0, busy=fs.readfile('/tmp/router-docker168.busy') or '',
        last_result=fs.readfile('/tmp/router-docker168.result') or ''
    }
    require('luci.http').write_json(result)
end
