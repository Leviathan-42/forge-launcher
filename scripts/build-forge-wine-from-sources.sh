#!/usr/bin/env bash
set -euo pipefail

# Build a Forge-owned Wine runtime from the local Wine source tree.
# This does not use any paid app runtime or bottle.
#
# Defaults are tuned for Apple Silicon building an x86_64 Wine under Rosetta.
# The x86_64 MoltenVK dylib bundled by Wine Devel is used only as a build/link
# dependency so configure can define SONAME_LIBVULKAN. At runtime Forge still
# owns the Wine prefix and can point Vulkan at its configured MoltenVK ICD.
#
# Usage:
#   scripts/build-forge-wine-from-sources.sh
#   SOURCES_DIR="$HOME/Downloads/sources" scripts/build-forge-wine-from-sources.sh
#   INSTALL_PREFIX="$HOME/Wine/Runtimes/forge-wine-11-full" scripts/build-forge-wine-from-sources.sh

SOURCES_DIR="${SOURCES_DIR:-$HOME/Downloads/sources}"
WINE_SRC="$SOURCES_DIR/wine"
BUILD_DIR="${BUILD_DIR:-$WINE_SRC/build-forge64-full}"
INSTALL_PREFIX="${INSTALL_PREFIX:-$HOME/Wine/Runtimes/forge-wine-11-full}"
WINE_DEVEL_LIB="${WINE_DEVEL_LIB:-/Applications/Wine Devel.app/Contents/Resources/wine/lib}"
MOLTENVK_LINK_DIR="${MOLTENVK_LINK_DIR:-/tmp/forge-wine-devel-lib}"
JOBS="${JOBS:-$(sysctl -n hw.activecpu)}"
ENABLE_WOW64="${ENABLE_WOW64:-0}"

if [[ ! -d "$WINE_SRC" ]]; then
  echo "Wine source not found: $WINE_SRC" >&2
  exit 1
fi

if [[ ! -f "$WINE_DEVEL_LIB/libMoltenVK.dylib" ]]; then
  echo "x86_64 libMoltenVK.dylib not found: $WINE_DEVEL_LIB/libMoltenVK.dylib" >&2
  echo "Install Wine Devel or set WINE_DEVEL_LIB to a directory with an x86_64 libMoltenVK.dylib." >&2
  exit 1
fi

apply_forge_steam_patch() {
  local process_c="$WINE_SRC/dlls/kernelbase/process.c"
  python3 - "$process_c" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
if "forge_append_steamwebhelper_args" in text:
    print("Forge Steam webhelper Wine patch already present")
    raise SystemExit
marker = """ done:\n    RtlFreeHeap( GetProcessHeap(), 0, name );\n    return ret;\n}\n\n\n/***********************************************************************\n *           create_process_params\n */"""
insert = """ done:\n    RtlFreeHeap( GetProcessHeap(), 0, name );\n    return ret;\n}\n\n/* Forge Steam CEF workaround.\n *\n * Steam's Chromium helper needs these flags under Forge Wine 11 to avoid a\n * black CEF window. Apply the workaround only to steamwebhelper.exe so games\n * launched by Steam keep their normal graphics backend.\n */\nstatic BOOL containsiW( const WCHAR *str, const WCHAR *sub )\n{\n    SIZE_T len;\n\n    if (!str || !sub) return FALSE;\n    len = lstrlenW( sub );\n    if (!len) return TRUE;\n    for (; *str; str++) if (!wcsnicmp( str, sub, len )) return TRUE;\n    return FALSE;\n}\n\nstatic WCHAR *forge_append_steamwebhelper_args( const WCHAR *app_name, WCHAR *cmdline )\n{\n    static const WCHAR helperW[] = L\"steamwebhelper.exe\";\n    static const WCHAR crashpadW[] = L\"--type=crashpad-handler\";\n    static const WCHAR flagsW[] = L\" --no-sandbox --in-process-gpu --disable-gpu\";\n    WCHAR *ret;\n    SIZE_T len, flags_len;\n\n    if (!cmdline) return cmdline;\n    if (!containsiW( app_name, helperW ) && !containsiW( cmdline, helperW )) return cmdline;\n    if (containsiW( cmdline, crashpadW )) return cmdline;\n    if (containsiW( cmdline, L\"--in-process-gpu\" ) && containsiW( cmdline, L\"--disable-gpu\" ))\n        return cmdline;\n\n    len = lstrlenW( cmdline );\n    flags_len = lstrlenW( flagsW );\n    if (!(ret = HeapAlloc( GetProcessHeap(), 0, (len + flags_len + 1) * sizeof(WCHAR) )))\n        return cmdline;\n    memcpy( ret, cmdline, len * sizeof(WCHAR) );\n    memcpy( ret + len, flagsW, (flags_len + 1) * sizeof(WCHAR) );\n    FIXME( \"HACK: appending Steam webhelper CEF flags\\n\" );\n    return ret;\n}\n\n\n/***********************************************************************\n *           create_process_params\n */"""
if marker not in text:
    raise SystemExit("Could not locate helper insertion point in process.c")
text = text.replace(marker, insert, 1)
marker = """    /* CW Hack 24920, 24557 */\n    {\n        char sgi[64];\n\n        if (cmd_line && !wcsncmp( cmd_line, L\"powershell\", 10 )\n            && GetEnvironmentVariableA( \"SteamGameId\", sgi, sizeof(sgi) ) < sizeof(sgi) && !strcmp( sgi, \"2767030\" ))\n        {\n            FIXME(\"HACK: not starting powershell.exe.\\n\");\n            SetLastError( ERROR_FILE_NOT_FOUND );\n            return FALSE;\n        }\n    }\n\n    /* Warn if unsupported features are used */"""
insert = """    /* CW Hack 24920, 24557 */\n    {\n        char sgi[64];\n\n        if (cmd_line && !wcsncmp( cmd_line, L\"powershell\", 10 )\n            && GetEnvironmentVariableA( \"SteamGameId\", sgi, sizeof(sgi) ) < sizeof(sgi) && !strcmp( sgi, \"2767030\" ))\n        {\n            FIXME(\"HACK: not starting powershell.exe.\\n\");\n            SetLastError( ERROR_FILE_NOT_FOUND );\n            return FALSE;\n        }\n    }\n\n    {\n        WCHAR *old_cmdline = tidy_cmdline;\n        tidy_cmdline = forge_append_steamwebhelper_args( app_name, tidy_cmdline );\n        if (old_cmdline != tidy_cmdline && old_cmdline != cmd_line)\n            HeapFree( GetProcessHeap(), 0, old_cmdline );\n    }\n\n    /* Warn if unsupported features are used */"""
if marker not in text:
    raise SystemExit("Could not locate CreateProcess insertion point in process.c")
text = text.replace(marker, insert, 1)
path.write_text(text)
print("Applied Forge Steam webhelper Wine patch")
PY
}

mkdir -p "$(dirname "$MOLTENVK_LINK_DIR")" "$(dirname "$BUILD_DIR")" "$INSTALL_PREFIX"
ln -sfn "$WINE_DEVEL_LIB" "$MOLTENVK_LINK_DIR"

export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/bin:$PATH"
export SDKROOT="${SDKROOT:-$(xcode-select -p)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk}"
export CPPFLAGS="${CPPFLAGS:--I/opt/homebrew/include -I/opt/homebrew/include/freetype2}"
# Prefer x86_64 dylibs from Wine Devel when building under Rosetta; Homebrew on
# Apple Silicon is arm64 and cannot satisfy x86_64 configure/link checks.
export LDFLAGS="${LDFLAGS:--L$MOLTENVK_LINK_DIR -L/opt/homebrew/lib}"
export FREETYPE_CFLAGS="${FREETYPE_CFLAGS:--I/opt/homebrew/include/freetype2}"
export FREETYPE_LIBS="${FREETYPE_LIBS:--L$MOLTENVK_LINK_DIR -lfreetype}"
export GNUTLS_CFLAGS="${GNUTLS_CFLAGS:--I/opt/homebrew/include}"
export GNUTLS_LIBS="${GNUTLS_LIBS:--L$MOLTENVK_LINK_DIR -lgnutls}"

apply_forge_steam_game_env_patch() {
  local process_c="$WINE_SRC/dlls/kernelbase/process.c"
  python3 - "$process_c" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
latest_game_env_vars = [
    "FORGE_GAME_WINE_D3D_CONFIG",
    "FORGE_GAME_LIBGL_ALWAYS_SOFTWARE",
    "FORGE_GAME_VK_DRIVER_FILES",
    "FORGE_GAME_MTL_HUD_LAYER",
    "FORGE_GAME_DXVK_ASYNC",
]
if "forge_make_steam_game_env" in text and all(var in text for var in latest_game_env_vars):
    print("Forge Steam game-env Wine patch already present")
    raise SystemExit
marker = '''    FIXME( "HACK: appending Steam webhelper CEF flags\\n" );
    return ret;
}


/***********************************************************************
 *           create_process_params
 */'''
helpers = '''    FIXME( "HACK: appending Steam webhelper CEF flags\\n" );
    return ret;
}

static BOOL forge_env_flag_enabled( const WCHAR *name )
{
    WCHAR value[8];
    DWORD len = GetEnvironmentVariableW( name, value, ARRAY_SIZE( value ) );
    return len && len < ARRAY_SIZE( value ) && value[0] == '1';
}

static BOOL forge_has_steam_game_env(void)
{
    return GetEnvironmentVariableW( L"FORGE_GAME_WINEDLLOVERRIDES", NULL, 0 ) ||
           GetEnvironmentVariableW( L"FORGE_GAME_WINE_D3D_CONFIG", NULL, 0 ) ||
           GetEnvironmentVariableW( L"FORGE_GAME_VK_ICD_FILENAMES", NULL, 0 ) ||
           GetEnvironmentVariableW( L"FORGE_GAME_DYLD_LIBRARY_PATH", NULL, 0 );
}

static BOOL forge_is_steam_ui_process( const WCHAR *app_name, const WCHAR *cmdline )
{
    if (containsiW( app_name, L"steam.exe" ) || containsiW( cmdline, L"steam.exe" )) return TRUE;
    if (containsiW( app_name, L"steamwebhelper.exe" ) || containsiW( cmdline, L"steamwebhelper.exe" )) return TRUE;
    if (containsiW( app_name, L"steamservice.exe" ) || containsiW( cmdline, L"steamservice.exe" )) return TRUE;
    if (containsiW( app_name, L"steamerrorreporter.exe" ) || containsiW( cmdline, L"steamerrorreporter.exe" )) return TRUE;
    if (containsiW( app_name, L"crashhandler" ) || containsiW( cmdline, L"crashhandler" )) return TRUE;
    if (containsiW( app_name, L"gldriverquery.exe" ) || containsiW( cmdline, L"gldriverquery.exe" )) return TRUE;
    if (containsiW( app_name, L"vulkandriverquery.exe" ) || containsiW( cmdline, L"vulkandriverquery.exe" )) return TRUE;
    if (containsiW( app_name, L"\\\\steam\\\\bin\\\\" ) || containsiW( cmdline, L"\\\\steam\\\\bin\\\\" )) return TRUE;
    if (containsiW( app_name, L"\\\\steam\\\\clientui\\\\" ) || containsiW( cmdline, L"\\\\steam\\\\clientui\\\\" )) return TRUE;
    return FALSE;
}

static BOOL forge_env_entry_matches( const WCHAR *entry, const WCHAR *name )
{
    SIZE_T len = lstrlenW( name );
    return !wcsnicmp( entry, name, len ) && entry[len] == '=';
}

static BOOL forge_drop_steam_safe_env_entry( const WCHAR *entry )
{
    return forge_env_entry_matches( entry, L"FORGE_STEAM_SAFE_MODE" ) ||
           forge_env_entry_matches( entry, L"FORGE_GAME_WINEDLLOVERRIDES" ) ||
           forge_env_entry_matches( entry, L"FORGE_GAME_WINE_D3D_CONFIG" ) ||
           forge_env_entry_matches( entry, L"FORGE_GAME_LIBGL_ALWAYS_SOFTWARE" ) ||
           forge_env_entry_matches( entry, L"FORGE_GAME_VK_ICD_FILENAMES" ) ||
           forge_env_entry_matches( entry, L"FORGE_GAME_VK_DRIVER_FILES" ) ||
           forge_env_entry_matches( entry, L"FORGE_GAME_MTL_HUD_ENABLED" ) ||
           forge_env_entry_matches( entry, L"FORGE_GAME_MTL_HUD_LAYER" ) ||
           forge_env_entry_matches( entry, L"FORGE_GAME_DXVK_ASYNC" ) ||
           forge_env_entry_matches( entry, L"FORGE_GAME_DYLD_LIBRARY_PATH" ) ||
           forge_env_entry_matches( entry, L"FORGE_GAME_WINEDLLPATH" ) ||
           forge_env_entry_matches( entry, L"WINEDLLOVERRIDES" ) ||
           forge_env_entry_matches( entry, L"WINE_D3D_CONFIG" ) ||
           forge_env_entry_matches( entry, L"LIBGL_ALWAYS_SOFTWARE" ) ||
           forge_env_entry_matches( entry, L"VK_ICD_FILENAMES" ) ||
           forge_env_entry_matches( entry, L"VK_DRIVER_FILES" ) ||
           forge_env_entry_matches( entry, L"DXVK_FILTER_DEVICE_NAME" ) ||
           forge_env_entry_matches( entry, L"DXVK_ASYNC" ) ||
           forge_env_entry_matches( entry, L"MTL_HUD_ENABLED" ) ||
           forge_env_entry_matches( entry, L"MTL_HUD_LAYER" ) ||
           forge_env_entry_matches( entry, L"DYLD_LIBRARY_PATH" ) ||
           forge_env_entry_matches( entry, L"WINEDLLPATH" );
}

static WCHAR *forge_dup_env_value( const WCHAR *name )
{
    DWORD len = GetEnvironmentVariableW( name, NULL, 0 );
    WCHAR *ret;

    if (!len) return NULL;
    if (!(ret = HeapAlloc( GetProcessHeap(), 0, len * sizeof(WCHAR) ))) return NULL;
    if (!GetEnvironmentVariableW( name, ret, len ))
    {
        HeapFree( GetProcessHeap(), 0, ret );
        return NULL;
    }
    return ret;
}

static SIZE_T forge_env_pair_len( const WCHAR *name, const WCHAR *value )
{
    if (!value || !value[0]) return 0;
    return lstrlenW( name ) + 1 + lstrlenW( value ) + 1;
}

static WCHAR *forge_append_env_pair( WCHAR *dst, const WCHAR *name, const WCHAR *value )
{
    SIZE_T len;

    if (!value || !value[0]) return dst;
    len = lstrlenW( name );
    memcpy( dst, name, len * sizeof(WCHAR) );
    dst += len;
    *dst++ = '=';
    len = lstrlenW( value );
    memcpy( dst, value, len * sizeof(WCHAR) );
    dst += len;
    *dst++ = 0;
    return dst;
}

static WCHAR *forge_make_steam_game_env( const void *env, DWORD flags )
{
    const WCHAR *base = NULL, *p;
    WCHAR *owned_base = NULL, *ret = NULL, *dst;
    WCHAR *game_dlls = forge_dup_env_value( L"FORGE_GAME_WINEDLLOVERRIDES" );
    WCHAR *game_wined3d = forge_dup_env_value( L"FORGE_GAME_WINE_D3D_CONFIG" );
    WCHAR *game_libgl = forge_dup_env_value( L"FORGE_GAME_LIBGL_ALWAYS_SOFTWARE" );
    WCHAR *game_vk = forge_dup_env_value( L"FORGE_GAME_VK_ICD_FILENAMES" );
    WCHAR *game_vk_driver = forge_dup_env_value( L"FORGE_GAME_VK_DRIVER_FILES" );
    WCHAR *game_hud = forge_dup_env_value( L"FORGE_GAME_MTL_HUD_ENABLED" );
    WCHAR *game_hud_layer = forge_dup_env_value( L"FORGE_GAME_MTL_HUD_LAYER" );
    WCHAR *game_dxvk_async = forge_dup_env_value( L"FORGE_GAME_DXVK_ASYNC" );
    WCHAR *game_dyld = forge_dup_env_value( L"FORGE_GAME_DYLD_LIBRARY_PATH" );
    WCHAR *game_winedllpath = forge_dup_env_value( L"FORGE_GAME_WINEDLLPATH" );
    BOOL free_env_strings = FALSE;
    SIZE_T total = 1;

    if (env)
    {
        if (flags & CREATE_UNICODE_ENVIRONMENT) base = env;
        else
        {
            const char *e = env;
            DWORD lenW;
            while (*e) e += strlen(e) + 1;
            e++;
            lenW = MultiByteToWideChar( CP_ACP, 0, env, e - (const char *)env, NULL, 0 );
            if (!(owned_base = HeapAlloc( GetProcessHeap(), 0, lenW * sizeof(WCHAR) ))) goto done;
            MultiByteToWideChar( CP_ACP, 0, env, e - (const char *)env, owned_base, lenW );
            base = owned_base;
        }
    }
    else
    {
        if (!(owned_base = GetEnvironmentStringsW())) goto done;
        base = owned_base;
        free_env_strings = TRUE;
    }

    for (p = base; *p; p += lstrlenW( p ) + 1)
        if (!forge_drop_steam_safe_env_entry( p )) total += lstrlenW( p ) + 1;
    total += forge_env_pair_len( L"WINEDLLOVERRIDES", game_dlls );
    total += forge_env_pair_len( L"WINE_D3D_CONFIG", game_wined3d );
    total += forge_env_pair_len( L"LIBGL_ALWAYS_SOFTWARE", game_libgl );
    total += forge_env_pair_len( L"VK_ICD_FILENAMES", game_vk );
    total += forge_env_pair_len( L"VK_DRIVER_FILES", game_vk_driver );
    total += forge_env_pair_len( L"MTL_HUD_ENABLED", game_hud );
    total += forge_env_pair_len( L"MTL_HUD_LAYER", game_hud_layer );
    total += forge_env_pair_len( L"DXVK_ASYNC", game_dxvk_async );
    total += forge_env_pair_len( L"DYLD_LIBRARY_PATH", game_dyld );
    total += forge_env_pair_len( L"WINEDLLPATH", game_winedllpath );

    if (!(ret = HeapAlloc( GetProcessHeap(), 0, total * sizeof(WCHAR) ))) goto done;

    dst = ret;
    for (p = base; *p; p += lstrlenW( p ) + 1)
    {
        SIZE_T len;
        if (forge_drop_steam_safe_env_entry( p )) continue;
        len = lstrlenW( p ) + 1;
        memcpy( dst, p, len * sizeof(WCHAR) );
        dst += len;
    }
    dst = forge_append_env_pair( dst, L"WINEDLLOVERRIDES", game_dlls );
    dst = forge_append_env_pair( dst, L"WINE_D3D_CONFIG", game_wined3d );
    dst = forge_append_env_pair( dst, L"LIBGL_ALWAYS_SOFTWARE", game_libgl );
    dst = forge_append_env_pair( dst, L"VK_ICD_FILENAMES", game_vk );
    dst = forge_append_env_pair( dst, L"VK_DRIVER_FILES", game_vk_driver );
    dst = forge_append_env_pair( dst, L"MTL_HUD_ENABLED", game_hud );
    dst = forge_append_env_pair( dst, L"MTL_HUD_LAYER", game_hud_layer );
    dst = forge_append_env_pair( dst, L"DXVK_ASYNC", game_dxvk_async );
    dst = forge_append_env_pair( dst, L"DYLD_LIBRARY_PATH", game_dyld );
    dst = forge_append_env_pair( dst, L"WINEDLLPATH", game_winedllpath );
    *dst = 0;

 done:
    if (owned_base)
    {
        if (free_env_strings) FreeEnvironmentStringsW( owned_base );
        else HeapFree( GetProcessHeap(), 0, owned_base );
    }
    HeapFree( GetProcessHeap(), 0, game_dlls );
    HeapFree( GetProcessHeap(), 0, game_wined3d );
    HeapFree( GetProcessHeap(), 0, game_libgl );
    HeapFree( GetProcessHeap(), 0, game_vk );
    HeapFree( GetProcessHeap(), 0, game_vk_driver );
    HeapFree( GetProcessHeap(), 0, game_hud );
    HeapFree( GetProcessHeap(), 0, game_hud_layer );
    HeapFree( GetProcessHeap(), 0, game_dxvk_async );
    HeapFree( GetProcessHeap(), 0, game_dyld );
    HeapFree( GetProcessHeap(), 0, game_winedllpath );
    return ret;
}


/***********************************************************************
 *           create_process_params
 */'''
if "forge_make_steam_game_env" in text:
    create_marker = '''


/***********************************************************************
 *           create_process_params
 */'''
    helper_start = text.find("static BOOL forge_env_flag_enabled")
    helper_end = text.find(create_marker, helper_start)
    fresh_start = helpers.find("static BOOL forge_env_flag_enabled")
    if helper_start < 0 or helper_end < 0 or fresh_start < 0:
        raise SystemExit("Could not locate existing Forge Steam game-env helper block in process.c")
    text = text[:helper_start] + helpers[fresh_start:] + text[helper_end + len(create_marker):]
    path.write_text(text)
    print("Upgraded Forge Steam game-env Wine patch")
    raise SystemExit
if marker not in text:
    raise SystemExit("Could not locate Steam helper block for game-env insertion in process.c")
text = text.replace(marker, helpers, 1)
text = text.replace("    WCHAR *p, *tidy_cmdline = cmd_line;\n    RTL_USER_PROCESS_PARAMETERS *params = NULL;",
                    "    WCHAR *p, *tidy_cmdline = cmd_line;\n    WCHAR *forge_game_env = NULL;\n    RTL_USER_PROCESS_PARAMETERS *params = NULL;", 1)
needle = '''    {
        WCHAR *old_cmdline = tidy_cmdline;
        tidy_cmdline = forge_append_steamwebhelper_args( app_name, tidy_cmdline );
        if (old_cmdline != tidy_cmdline && old_cmdline != cmd_line)
            HeapFree( GetProcessHeap(), 0, old_cmdline );
    }

    /* Warn if unsupported features are used */'''
insert = '''    {
        WCHAR *old_cmdline = tidy_cmdline;
        tidy_cmdline = forge_append_steamwebhelper_args( app_name, tidy_cmdline );
        if (old_cmdline != tidy_cmdline && old_cmdline != cmd_line)
            HeapFree( GetProcessHeap(), 0, old_cmdline );
    }

    if ((forge_env_flag_enabled( L"FORGE_STEAM_SAFE_MODE" ) || forge_has_steam_game_env()) &&
        !forge_is_steam_ui_process( app_name, tidy_cmdline ))
    {
        if ((forge_game_env = forge_make_steam_game_env( env, flags )))
        {
            env = forge_game_env;
            flags |= CREATE_UNICODE_ENVIRONMENT;
            WARN( "HACK: restoring Forge game graphics env for Steam child process %s\\n", debugstr_w(app_name) );
        }
    }

    /* Warn if unsupported features are used */'''
if needle not in text:
    raise SystemExit("Could not locate Steam helper call block for game-env insertion in process.c")
text = text.replace(needle, insert, 1)
text = text.replace("    RtlDestroyProcessParameters( params );\n    if (tidy_cmdline != cmd_line) HeapFree( GetProcessHeap(), 0, tidy_cmdline );",
                    "    RtlDestroyProcessParameters( params );\n    if (forge_game_env) HeapFree( GetProcessHeap(), 0, forge_game_env );\n    if (tidy_cmdline != cmd_line) HeapFree( GetProcessHeap(), 0, tidy_cmdline );", 1)
path.write_text(text)
print("Applied Forge Steam game-env Wine patch")
PY
}

apply_forge_user_branding_patches() {
  python3 - "$WINE_SRC" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
bad_user = "cross" + "over"
bad_brand = "Cross" + "Over"

advapi = root / "dlls/advapi32/advapi.c"
text = advapi.read_text()
old_a = f'''    /* {bad_brand} Hack 12735: Use a consistent username */
    if (!getenv( "CX_REPORT_REAL_USERNAME" ))
    {{
        len = sizeof("{bad_user}");
        if ((ret = (len <= *size))) strcpy( name, "{bad_user}" );
        else SetLastError( ERROR_INSUFFICIENT_BUFFER );
        *size = len;
        return ret;
    }}'''
new_a = '''    /* Forge: use a stable launcher-owned Windows username. */
    if (!getenv( "FORGE_REPORT_REAL_USERNAME" ))
    {
        len = sizeof("forge");
        if ((ret = (len <= *size))) strcpy( name, "forge" );
        else SetLastError( ERROR_INSUFFICIENT_BUFFER );
        *size = len;
        return ret;
    }'''
old_w = f'''    /* {bad_brand} Hack 12735: Use a consistent username */
    if (!getenv( "CX_REPORT_REAL_USERNAME" ))
    {{
        len = ARRAY_SIZE( L"{bad_user}" );
        if ((ret = (len <= *size))) wcscpy( name, L"{bad_user}" );
        else SetLastError( ERROR_INSUFFICIENT_BUFFER );
        *size = len;
        return ret;
    }}'''
new_w = '''    /* Forge: use a stable launcher-owned Windows username. */
    if (!getenv( "FORGE_REPORT_REAL_USERNAME" ))
    {
        len = ARRAY_SIZE( L"forge" );
        if ((ret = (len <= *size))) wcscpy( name, L"forge" );
        else SetLastError( ERROR_INSUFFICIENT_BUFFER );
        *size = len;
        return ret;
    }'''
text = text.replace(old_a, new_a).replace(old_w, new_w)
advapi.write_text(text)

shellpath = root / "dlls/shell32/shellpath.c"
text = shellpath.read_text()
old = f'''        else if (!wcsnicmp(szTemp, L"%USERPROFILE%", lstrlenW(L"%USERPROFILE%")))
        {{
            /* {bad_brand} Hack 12735 */
            static const WCHAR userName[] = {{'c','r','o','s','s','o','v','e','r',0}};

            lstrcpyW(szDest, szProfilesPrefix);
            PathAppendW(szDest, userName);
            PathAppendW(szDest, szTemp + lstrlenW(L"%USERPROFILE%"));
        }}'''
new = '''        else if (!wcsnicmp(szTemp, L"%USERPROFILE%", lstrlenW(L"%USERPROFILE%")))
        {
            /* Forge: use the launcher-owned Windows profile name. */
            static const WCHAR userName[] = {'f','o','r','g','e',0};

            lstrcpyW(szDest, szProfilesPrefix);
            PathAppendW(szDest, userName);
            PathAppendW(szDest, szTemp + lstrlenW(L"%USERPROFILE%"));
        }'''
text = text.replace(old, new)
shellpath.write_text(text)

shlexec = root / "dlls/shell32/shlexec.c"
text = shlexec.read_text()
text = text.replace("SHELL_" + bad_brand + "Fallback", "SHELL_ForgeFallback")
text = text.replace(bad_brand + " Hack 2412", "Forge native fallback")
text = text.replace("NO" + bad_brand.upper() + "FALLBACK", "NOFORGEFALLBACK")
text = text.replace("No" + bad_brand + "Fallback", "NoForgeFallback")
text = text.replace("Trying " + bad_brand + "Fallback", "Trying ForgeFallback")
text = text.replace(bad_brand + "Fallback", "ForgeFallback")
shlexec.write_text(text)
print("Applied Forge username/profile branding Wine patches")
PY
}

apply_forge_overwatch_stack_patch() {
  local virtual_c="$WINE_SRC/dlls/ntdll/unix/virtual.c"
  local signal_c="$WINE_SRC/dlls/ntdll/unix/signal_x86_64.c"
  local unix_private_h="$WINE_SRC/dlls/ntdll/unix/unix_private.h"
  python3 - "$virtual_c" "$signal_c" "$unix_private_h" <<'PY'
import pathlib, sys
virtual_c = pathlib.Path(sys.argv[1])
signal_c = pathlib.Path(sys.argv[2])
unix_private_h = pathlib.Path(sys.argv[3])

text = unix_private_h.read_text()
if "virtual_handle_stack_overflow_retry" not in text:
    old = 'extern NTSTATUS virtual_handle_fault( EXCEPTION_RECORD *rec, void *stack );\nextern unsigned int virtual_locked_server_call( void *req_ptr );'
    new = 'extern NTSTATUS virtual_handle_fault( EXCEPTION_RECORD *rec, void *stack );\nextern BOOL virtual_handle_stack_overflow_retry( void *stack, void *addr, void **new_stack );\nextern unsigned int virtual_locked_server_call( void *req_ptr );'
    if old not in text:
        raise SystemExit("Could not locate virtual_handle_fault declaration in unix_private.h")
    unix_private_h.write_text(text.replace(old, new, 1))

text = virtual_c.read_text()
if "forge_stack_guarantee_bytes" not in text:
    marker = '''/***********************************************************************
 *           is_inside_thread_stack
 */
static BOOL is_inside_thread_stack( void *ptr, struct thread_stack_info *stack )
{'''
    insert = '''static SIZE_T forge_stack_guarantee_bytes(void)
{
    const char *value = getenv( "FORGE_STACK_GUARANTEE_BYTES" );
    char *end;
    unsigned long long bytes;

    if (!value || !*value) return 0;
    bytes = strtoull( value, &end, 0 );
    if (end == value) return 0;
    if (bytes > 32 * 1024 * 1024) bytes = 32 * 1024 * 1024;
    return (bytes + host_page_size - 1) & ~(host_page_size - 1);
}

/***********************************************************************
 *           is_inside_thread_stack
 */
static BOOL is_inside_thread_stack( void *ptr, struct thread_stack_info *stack )
{'''
    if marker not in text:
        raise SystemExit("Could not locate is_inside_thread_stack in virtual.c")
    text = text.replace(marker, insert, 1)

repls = [
    ('''    stack->guaranteed = max( teb->GuaranteedStackBytes, min_guaranteed );
    stack->is_wow = FALSE;''',
     '''    stack->guaranteed = max( teb->GuaranteedStackBytes, min_guaranteed );
    stack->guaranteed = max( stack->guaranteed, forge_stack_guarantee_bytes() );
    stack->is_wow = FALSE;'''),
    ('''    stack->guaranteed = max( wow_teb->GuaranteedStackBytes, min_guaranteed );
    stack->is_wow = TRUE;''',
     '''    stack->guaranteed = max( wow_teb->GuaranteedStackBytes, min_guaranteed );
    stack->guaranteed = max( stack->guaranteed, forge_stack_guarantee_bytes() );
    stack->is_wow = TRUE;''')
]
for old, new in repls:
    if new not in text:
        if old not in text:
            raise SystemExit("Could not locate stack guarantee assignment in virtual.c")
        text = text.replace(old, new, 1)

if "virtual_handle_stack_overflow_retry" not in text:
    marker = '''/***********************************************************************
 *           virtual_handle_fault
 */
NTSTATUS virtual_handle_fault( EXCEPTION_RECORD *rec, void *stack )'''
    insert = '''/***********************************************************************
 *           virtual_handle_stack_overflow_retry
 *
 * Some protected game loaders intentionally run exception-handler code with
 * the guest stack already at the final stack page. If the handler prolog then
 * touches the uncommitted page, treating that write as a fresh Windows AV can
 * deadlock or spin under the loader lock. When explicitly enabled, copy the
 * small call frame to the guaranteed stack band, switch RSP there, and retry
 * the original instruction instead of creating a nested exception.
 */
BOOL virtual_handle_stack_overflow_retry( void *stack_ptr, void *fault_addr, void **new_stack )
{
    char *stack = stack_ptr;
    char *addr = ROUND_ADDR( fault_addr, host_page_mask );
    struct thread_stack_info stack_info;
    SIZE_T guarantee = forge_stack_guarantee_bytes();
    char *base, *top, *dst;
    SIZE_T copy_size = 0x100;

    if (!guarantee || !is_inside_thread_stack( stack, &stack_info )) return FALSE;

    base = stack_info.start;
    top = stack_info.start + host_page_size + guarantee;
    if (top > stack_info.end) top = stack_info.end;
    if (addr < base || addr >= top) return FALSE;
    if (stack < base || stack >= top) return FALSE;
    if (top <= stack_info.start + host_page_size + copy_size) return FALSE;

    mutex_lock( &virtual_mutex );  /* no need for signal masking inside signal handler */
    set_page_vprot_bits( base, top - base, VPROT_COMMITTED, VPROT_GUARD );
    mprotect_range( base, top - base, 0, 0 );
    mutex_unlock( &virtual_mutex );

    dst = (char *)((ULONG_PTR)(top - copy_size) & ~(ULONG_PTR)15);
    memcpy( dst, stack, copy_size );
    *new_stack = dst;
    WARN( "Forge retrying low-stack write addr %p stack %p -> %p (%p-%p-%p)\\n",
          fault_addr, stack, dst, stack_info.start, stack_info.limit, stack_info.end );
    return TRUE;
}


/***********************************************************************
 *           virtual_handle_fault
 */
NTSTATUS virtual_handle_fault( EXCEPTION_RECORD *rec, void *stack )'''
    if marker not in text:
        raise SystemExit("Could not locate virtual_handle_fault in virtual.c")
    text = text.replace(marker, insert, 1)

if "Forge relocating low-stack exception frame" not in text:
    old = '''    if (!is_inside_thread_stack( stack, &stack_info ))
    {
        if (is_inside_signal_stack( stack ))
        {
            ERR( "nested exception on signal stack addr %p stack %p\\n", rec->ExceptionAddress, stack );
            abort_thread(1);
        }
        WARN( "exception outside of stack limits addr %p stack %p (%p-%p-%p)\\n",
              rec->ExceptionAddress, stack, NtCurrentTeb()->DeallocationStack,
              NtCurrentTeb()->Tib.StackLimit, NtCurrentTeb()->Tib.StackBase );
        return stack - size;
    }'''
    new = '''    if (!is_inside_thread_stack( stack, &stack_info ))
    {
        if (is_inside_signal_stack( stack ))
        {
            ERR( "nested exception on signal stack addr %p stack %p\\n", rec->ExceptionAddress, stack );
            abort_thread(1);
        }
        {
            SIZE_T guarantee = forge_stack_guarantee_bytes();
            TEB *teb = NtCurrentTeb();
            char *start = teb->DeallocationStack;
            char *end = teb->Tib.StackBase;
            char *base = start;
            char *top = start + host_page_size + guarantee;
            char *old_stack = stack;

            if (guarantee && stack >= start - host_page_size && stack < start)
            {
                if (top > end) top = end;
                if (top > start + host_page_size + size)
                {
                    mutex_lock( &virtual_mutex );  /* no need for signal masking inside signal handler */
                    set_page_vprot_bits( base, top - base, VPROT_COMMITTED, VPROT_GUARD );
                    mprotect_range( base, top - base, 0, 0 );
                    mutex_unlock( &virtual_mutex );

                    stack = (char *)((ULONG_PTR)(top - size) & ~(ULONG_PTR)63);
                    WARN( "Forge relocating low-stack exception frame addr %p stack %p -> %p (%p-%p-%p)\\n",
                          rec->ExceptionAddress, old_stack, stack, teb->DeallocationStack,
                          teb->Tib.StackLimit, teb->Tib.StackBase );
                    return stack;
                }
            }
        }
        WARN( "exception outside of stack limits addr %p stack %p (%p-%p-%p)\\n",
              rec->ExceptionAddress, stack, NtCurrentTeb()->DeallocationStack,
              NtCurrentTeb()->Tib.StackLimit, NtCurrentTeb()->Tib.StackBase );
        return stack - size;
    }'''
    if old not in text:
        raise SystemExit("Could not locate outside-stack exception block in virtual.c")
    text = text.replace(old, new, 1)

if "Forge relocating stack-overflow exception frame" not in text:
    old = '''    if (stack < stack_info.start + host_page_size)
    {
        /* stack overflow on last page, unrecoverable */
        UINT diff = stack_info.start + host_page_size - stack;
        ERR( "stack overflow %u bytes addr %p stack %p (%p-%p-%p)\\n",
             diff, rec->ExceptionAddress, stack, stack_info.start, stack_info.limit, stack_info.end );
        abort_thread(1);
    }'''
    new = '''    if (stack < stack_info.start + host_page_size)
    {
        SIZE_T guarantee = forge_stack_guarantee_bytes();
        char *base = stack_info.start;
        char *top = stack_info.start + host_page_size + guarantee;

        if (guarantee)
        {
            if (top > stack_info.end) top = stack_info.end;
            if (top > stack_info.start + host_page_size + size)
            {
                mutex_lock( &virtual_mutex );  /* no need for signal masking inside signal handler */
                set_page_vprot_bits( base, top - base, VPROT_COMMITTED, VPROT_GUARD );
                mprotect_range( base, top - base, 0, 0 );
                mutex_unlock( &virtual_mutex );

                stack = (char *)((ULONG_PTR)(top - size) & ~(ULONG_PTR)63);
                WARN( "Forge relocating stack-overflow exception frame addr %p -> %p (%p-%p-%p)\\n",
                      rec->ExceptionAddress, stack, stack_info.start, stack_info.limit, stack_info.end );
                return stack;
            }
        }
        /* stack overflow on last page, unrecoverable */
        {
            UINT diff = stack_info.start + host_page_size - stack;
            ERR( "stack overflow %u bytes addr %p stack %p (%p-%p-%p)\\n",
                 diff, rec->ExceptionAddress, stack, stack_info.start, stack_info.limit, stack_info.end );
            abort_thread(1);
        }
    }'''
    if old not in text:
        raise SystemExit("Could not locate final stack-overflow block in virtual.c")
    text = text.replace(old, new, 1)

virtual_c.write_text(text)

text = signal_c.read_text()
if "virtual_handle_stack_overflow_retry" not in text:
    old = '''        rec.NumberParameters = 2;
        rec.ExceptionInformation[0] = (ERROR_sig(ucontext) >> 1) & 0x09;
        rec.ExceptionInformation[1] = (ULONG_PTR)siginfo->si_addr;
        if (!virtual_handle_fault( &rec, (void *)RSP_sig(ucontext) ) || check_invalid_gsbase( ucontext ))'''
    new = '''        rec.NumberParameters = 2;
        rec.ExceptionInformation[0] = (ERROR_sig(ucontext) >> 1) & 0x09;
        rec.ExceptionInformation[1] = (ULONG_PTR)siginfo->si_addr;
        if (rec.ExceptionInformation[0] == EXCEPTION_WRITE_FAULT)
        {
            void *new_stack;
            if (virtual_handle_stack_overflow_retry( (void *)RSP_sig(ucontext),
                                                     (void *)rec.ExceptionInformation[1], &new_stack ))
            {
                RSP_sig(ucontext) = (ULONG_PTR)new_stack;
                leave_handler( ucontext );
                return;
            }
        }
        if (!virtual_handle_fault( &rec, (void *)RSP_sig(ucontext) ) || check_invalid_gsbase( ucontext ))'''
    if old not in text:
        raise SystemExit("Could not locate page-fault virtual_handle_fault call in signal_x86_64.c")
    text = text.replace(old, new, 1)


signal_c.write_text(text)

print("Applied Forge low-stack retry Wine patch")
PY
}

apply_forge_win32u_desktop_bootstrap_patch() {
  local class_c="$WINE_SRC/dlls/win32u/class.c"
  local winstation_c="$WINE_SRC/dlls/win32u/winstation.c"
  python3 - "$class_c" "$winstation_c" <<'PY'
import pathlib, re, sys

class_c = pathlib.Path(sys.argv[1])
winstation_c = pathlib.Path(sys.argv[2])

class_helper = '''static BOOL forge_wstr_contains_ascii( const WCHAR *haystack, const char *needle )
{
    SIZE_T len, i;

    if (!haystack || !needle || !*needle) return FALSE;
    len = strlen( needle );
    for (; *haystack; haystack++)
    {
        for (i = 0; i < len && haystack[i]; i++)
        {
            WCHAR ch = haystack[i];
            char c = needle[i];
            if (ch >= 'A' && ch <= 'Z') ch += 'a' - 'A';
            if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
            if (ch != (unsigned char)c) break;
        }
        if (i == len) return TRUE;
    }
    return FALSE;
}

static BOOL forge_skip_desktop_window_bootstrap(void)
{
    const char *mode = getenv( "FORGE_SKIP_DESKTOP_WINDOW_BOOTSTRAP" );
    UNICODE_STRING *image;

    if (!mode || !*mode) return FALSE;
    if (!strcmp( mode, "all" )) return TRUE;
    image = &NtCurrentTeb()->Peb->ProcessParameters->ImagePathName;
    return forge_wstr_contains_ascii( image->Buffer, mode );
}

'''

text = class_c.read_text()
if "forge_skip_desktop_window_bootstrap" in text:
    text = re.sub(
        r'SYSTEM_BASIC_INFORMATION system_info;\n\n(?:static BOOL forge_wstr_contains_ascii\(.*?\n\n)?static BOOL forge_skip_desktop_window_bootstrap\(void\)\n\{.*?\}\n\n#define MAX_ATOM_LEN',
        'SYSTEM_BASIC_INFORMATION system_info;\n\n' + class_helper + '#define MAX_ATOM_LEN',
        text,
        count=1,
        flags=re.S,
    )
else:
    marker = 'SYSTEM_BASIC_INFORMATION system_info;\n\n#define MAX_ATOM_LEN'
    if marker not in text:
        raise SystemExit('Could not locate class.c helper insertion point')
    text = text.replace(marker, 'SYSTEM_BASIC_INFORMATION system_info;\n\n' + class_helper + '#define MAX_ATOM_LEN', 1)

text = text.replace(
    '    if (!is_builtin) get_desktop_window();',
    '    if (!is_builtin && !forge_skip_desktop_window_bootstrap()) get_desktop_window();',
    1,
)
text = text.replace(
    '    if (!is_desktop_class( name ) && !is_message_class( name )) get_desktop_window();',
    '    if (!forge_skip_desktop_window_bootstrap() &&\n        !is_desktop_class( name ) && !is_message_class( name )) get_desktop_window();',
    1,
)
class_c.write_text(text)

winstation_helper = '''static BOOL forge_wstr_contains_ascii( const WCHAR *str, const char *needle )
{
    SIZE_T len, i;

    if (!str || !needle || !*needle) return FALSE;
    len = strlen( needle );
    for (; *str; str++)
    {
        for (i = 0; i < len && str[i]; i++)
        {
            WCHAR ch = str[i];
            char c = needle[i];
            if (ch >= 'A' && ch <= 'Z') ch += 'a' - 'A';
            if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
            if (ch != (unsigned char)c) break;
        }
        if (i == len) return TRUE;
    }
    return FALSE;
}

static BOOL forge_skip_desktop_window_bootstrap(void)
{
    const char *mode = getenv( "FORGE_SKIP_DESKTOP_WINDOW_BOOTSTRAP" );
    UNICODE_STRING *image;

    if (!mode || !*mode) return FALSE;
    if (!strcmp( mode, "all" )) return TRUE;
    image = &NtCurrentTeb()->Peb->ProcessParameters->ImagePathName;
    return forge_wstr_contains_ascii( image->Buffer, mode );
}

'''

text = winstation_c.read_text()
if "forge_skip_desktop_window_bootstrap" in text:
    text = re.sub(
        r'\nstatic BOOL forge_wstr_contains_ascii\(.*?\n\nHWND get_desktop_window\(void\)',
        '\n' + winstation_helper + 'HWND get_desktop_window(void)',
        text,
        count=1,
        flags=re.S,
    )
    text = re.sub(
        r'\nstatic BOOL forge_skip_desktop_window_bootstrap\(void\)\n\{.*?\}\n\nHWND get_desktop_window\(void\)',
        '\n' + winstation_helper + 'HWND get_desktop_window(void)',
        text,
        count=1,
        flags=re.S,
    )
else:
    marker = '\nHWND get_desktop_window(void)'
    if marker not in text:
        raise SystemExit('Could not locate winstation.c helper insertion point')
    text = text.replace(marker, '\n' + winstation_helper + 'HWND get_desktop_window(void)', 1)

text = text.replace(
    '        req->force = is_service;',
    '        req->force = is_service || forge_skip_desktop_window_bootstrap();',
    1,
)
text = text.replace(
    '    else user_driver->pSetDesktopWindow( UlongToHandle( thread_info->top_window ));',
    '    else if (!forge_skip_desktop_window_bootstrap())\n        user_driver->pSetDesktopWindow( UlongToHandle( thread_info->top_window ));',
    1,
)
text = text.replace(
    '    register_builtin_classes();\n    return UlongToHandle( thread_info->top_window );',
    '    if (!forge_skip_desktop_window_bootstrap()) register_builtin_classes();\n    return UlongToHandle( thread_info->top_window );',
    1,
)
winstation_c.write_text(text)

print('Applied Forge win32u desktop-bootstrap skip patch')
PY
}

apply_forge_steam_patch
apply_forge_steam_game_env_patch
apply_forge_user_branding_patches
apply_forge_overwatch_stack_patch
apply_forge_win32u_desktop_bootstrap_patch

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [[ ! -f Makefile ]]; then
  arch_arg="--enable-win64"
  if [[ "$ENABLE_WOW64" == "1" ]]; then
    arch_arg="--enable-archs=i386,x86_64"
  fi

  arch -x86_64 ../configure -C \
    --prefix="$INSTALL_PREFIX" \
    "$arch_arg" \
    --with-mingw \
    --with-freetype \
    --with-gnutls \
    --without-gstreamer \
    --with-coreaudio \
    --without-cups \
    --with-vulkan \
    --without-x \
    --without-oss \
    --without-pulse \
    --without-alsa \
    --without-sdl \
    --without-udev \
    --without-usb \
    --without-netapi \
    --without-opencl \
    --without-pcap \
    --without-krb5 \
    --without-gettext
fi

# Configure can sometimes capture verbose macOS otool text for these SONAME
# constants. Force self-contained loader-relative dylib names before building.
if [[ -f include/config.h ]]; then
  /usr/bin/perl -0pi -e 's|#define SONAME_LIBFREETYPE .*|#define SONAME_LIBFREETYPE "@loader_path/../../libfreetype.dylib"|g; s|#define SONAME_LIBGNUTLS .*|#define SONAME_LIBGNUTLS "@loader_path/../../libgnutls.dylib"|g; s|#define SONAME_LIBVULKAN .*|#define SONAME_LIBVULKAN "@loader_path/../../libMoltenVK.dylib"|g' include/config.h
fi

arch -x86_64 make -j"$JOBS"
arch -x86_64 make install prefix="$INSTALL_PREFIX"

# Prune developer-only files; Forge ships/uses this as a launcher runtime, not
# as an SDK, and these files can contain upstream maintainer branding that is
# irrelevant to users.
rm -rf "$INSTALL_PREFIX/include" "$INSTALL_PREFIX/share/man" "$INSTALL_PREFIX/bin/winemaker"

# Bundle/link the small x86_64 runtime dylibs that this build dlopens/links by
# bare name. This keeps the installed runtime self-contained enough for Forge.
# Wine Devel is only the local source of these open runtime dylibs while building.
mkdir -p "$INSTALL_PREFIX/lib" "$INSTALL_PREFIX/lib/wine/x86_64-unix"
cp -a "$WINE_DEVEL_LIB"/*.dylib "$INSTALL_PREFIX/lib/" 2>/dev/null || true
cp "$WINE_DEVEL_LIB/libMoltenVK.dylib" "$INSTALL_PREFIX/lib/libMoltenVK.dylib"
cp "$WINE_DEVEL_LIB/libMoltenVK.dylib" "$INSTALL_PREFIX/lib/wine/x86_64-unix/libMoltenVK.dylib"
if [[ -f "$WINE_DEVEL_LIB/libinotify.dylib" ]]; then
  cp "$WINE_DEVEL_LIB/libinotify.dylib" "$INSTALL_PREFIX/lib/libinotify.dylib"
  cp "$WINE_DEVEL_LIB/libinotify.0.dylib" "$INSTALL_PREFIX/lib/libinotify.0.dylib" 2>/dev/null || true
  install_name_tool -change libinotify.dylib '@loader_path/../lib/libinotify.dylib' "$INSTALL_PREFIX/bin/wineserver" 2>/dev/null || true
  install_name_tool -change libinotify.dylib '@loader_path/../../libinotify.dylib' "$INSTALL_PREFIX/lib/wine/x86_64-unix/winebus.so" 2>/dev/null || true
fi

# We configure --without-usb, so remove the INF copy entry for wineusb.sys. If
# left in place, Wine's first-run setupapi pass can block on a missing resource.
if [[ -f "$INSTALL_PREFIX/share/wine/wine.inf" ]]; then
  /usr/bin/perl -0pi -e 's/^wineusb\.inf,"@%12%\\wineusb\.sys,-1"\n//m' "$INSTALL_PREFIX/share/wine/wine.inf"
fi

cat <<EOF

Forge Wine runtime installed:
  $INSTALL_PREFIX/bin/wine

Test Steam with:
  WINE="$INSTALL_PREFIX/bin/wine" scripts/test-steam-launch.sh
EOF
