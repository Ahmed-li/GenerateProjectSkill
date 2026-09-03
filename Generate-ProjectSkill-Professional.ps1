<#
.SYNOPSIS
    MAESTROSOFT - Professional Project Analysis & AI Skills Generator v3.0
    
.DESCRIPTION
    سكريبت احترافي لتحليل المشاريع وإنشاء:
    ✅ ملف JSON - موجهات (embeddings) وأرقام
    ✅ قاعدة بيانات SQLite - المشروع كاملاً
    ✅ ملف Markdown - Skills للنماذج الذكية (LLM)
    
.EXAMPLE
    .\Generate-ProjectSkill-Professional.ps1 -ProjectPath "C:\MyProject"
    
.NOTES
    Version: 3.0 Professional
    Created: 2026-09-03
#>

[CmdletBinding()]
param (
    [Parameter(HelpMessage = "مسار المشروع المراد تحليله")]
    [string]$ProjectPath,
    
    [Parameter(HelpMessage = "الحد الأقصى لحجم الملف (MB)")]
    [int]$MaxFileSizeMB = 10,
    
    [Parameter(HelpMessage = "عدد معالجات المعالجة")]
    [int]$ThreadCount = 4
)

# ==================== الإعدادات ====================
$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

$Colors = @{
    Success = 'Green'
    Error   = 'Red'
    Warning = 'Yellow'
    Info    = 'Cyan'
    Accent  = 'Magenta'
}

# ==================== دوال مساعدة ====================

function Show-Banner {
    Clear-Host
    Write-Host "`n$(('█' * 65))" -ForegroundColor $Colors.Accent
    Write-Host "  🚀 MAESTROSOFT - AI Skills Generator v3.0" -ForegroundColor $Colors.Accent
    Write-Host "  Professional Edition with Advanced Analytics" -ForegroundColor $Colors.Info
    Write-Host "$(('█' * 65))`n" -ForegroundColor $Colors.Accent
}

function Get-ProjectPath-Safe {
    param([string]$InputPath)
    
    if (-not [string]::IsNullOrWhiteSpace($InputPath)) {
        $InputPath = $InputPath.Trim('&', ' ', "'", '"', [char]0x200E, [char]0x200F)
    }
    
    if (-not $InputPath) {
        if ($PSScriptRoot -and (Test-Path -LiteralPath $PSScriptRoot)) {
            $InputPath = $PSScriptRoot
            Write-Host "📍 تم الكشف التلقائي عن المشروع: ✓" -ForegroundColor $Colors.Success
        } else {
            Write-Host "أدخل مسار المشروع:" -ForegroundColor $Colors.Warning
            $InputPath = Read-Host
        }
    }
    
    if (-not (Test-Path -LiteralPath $InputPath -PathType Container)) {
        Write-Host "❌ المسار غير صحيح!" -ForegroundColor $Colors.Error
        return $null
    }
    
    return (Resolve-Path -LiteralPath $InputPath).ProviderPath
}

function Get-TextEmbedding {
    param([string]$Text)
    
    # تحويل النص إلى أرقام (embeddings بسيطة)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $hash = (Get-FileHash -InputStream ([System.IO.MemoryStream]::new($bytes)) -Algorithm SHA256).Hash
    
    # تحويل الـ Hash إلى مصفوفة أرقام (vector)
    $vector = @()
    for ($i = 0; $i -lt $hash.Length; $i += 4) {
        $hex = $hash.Substring($i, 4)
        $decimal = [Convert]::ToInt32($hex, 16) % 1000
        $vector += [math]::Round($decimal / 1000, 3)
    }
    
    return $vector
}

function Initialize-SQLiteDatabase {
    param(
        [string]$DbPath,
        [string]$ProjectName
    )
    
    $sqlInit = @"
-- قاعدة بيانات المشروع - MAESTROSOFT AI Skills Database
-- Project: $ProjectName
-- Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

-- جدول المشروع
CREATE TABLE IF NOT EXISTS projects (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    path TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    total_files INTEGER DEFAULT 0,
    total_lines INTEGER DEFAULT 0,
    description TEXT
);

-- جدول الملفات
CREATE TABLE IF NOT EXISTS files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    relative_path TEXT NOT NULL,
    extension TEXT,
    category TEXT,
    file_size_kb REAL,
    lines_of_code INTEGER,
    char_count INTEGER,
    complexity_score REAL,
    hash_sha256 TEXT UNIQUE,
    content LONGTEXT,
    created_at DATETIME,
    modified_at DATETIME,
    embedding TEXT,
    FOREIGN KEY(project_id) REFERENCES projects(id)
);

-- جدول الفئات
CREATE TABLE IF NOT EXISTS categories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    file_count INTEGER DEFAULT 0
);

-- جدول الكلمات المفتاحية
CREATE TABLE IF NOT EXISTS keywords (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_id INTEGER NOT NULL,
    keyword TEXT NOT NULL,
    frequency INTEGER DEFAULT 1,
    FOREIGN KEY(file_id) REFERENCES files(id)
);

-- جدول الإحصائيات
CREATE TABLE IF NOT EXISTS statistics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    metric_name TEXT NOT NULL,
    metric_value TEXT,
    recorded_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(project_id) REFERENCES projects(id)
);

-- إنشاء الفهارس لتسريع البحث
CREATE INDEX IF NOT EXISTS idx_files_project ON files(project_id);
CREATE INDEX IF NOT EXISTS idx_files_category ON files(category);
CREATE INDEX IF NOT EXISTS idx_keywords_file ON keywords(file_id);
CREATE INDEX IF NOT EXISTS idx_files_hash ON files(hash_sha256);

-- عرض الإحصائيات
CREATE VIEW IF NOT EXISTS project_summary AS
SELECT 
    p.name as project_name,
    COUNT(DISTINCT f.id) as total_files,
    SUM(f.lines_of_code) as total_lines,
    SUM(f.file_size_kb) as total_size_kb,
    AVG(f.complexity_score) as avg_complexity
FROM projects p
LEFT JOIN files f ON p.id = f.project_id
GROUP BY p.id;
"@

    # حفظ الملف
    $sqlInit | Out-File -LiteralPath "$DbPath.init.sql" -Encoding UTF8 -Force
    
    return $sqlInit
}

function Connect-Database {
    param([string]$DbPath)
    
    try {
        $connection = New-Object System.Data.SQLite.SQLiteConnection
        $connection.ConnectionString = "Data Source=$DbPath;Version=3;Pooling=true;"
        $connection.Open()
        return $connection
    } catch {
        Write-Host "❌ فشل الاتصال بقاعدة البيانات: $($_.Exception.Message)" -ForegroundColor $Colors.Error
        return $null
    }
}

function Execute-SQLCommand {
    param(
        $Connection,
        [string]$CommandText
    )
    
    try {
        $command = $Connection.CreateCommand()
        $command.CommandText = $CommandText
        $command.ExecuteNonQuery() | Out-Null
        return $true
    } catch {
        Write-Host "⚠️ خطأ في تنفيذ أمر SQL: $($_.Exception.Message)" -ForegroundColor $Colors.Warning
        return $false
    }
}

function Insert-FileToDatabase {
    param(
        $Connection,
        [int]$ProjectId,
        [PSCustomObject]$FileData
    )
    
    $sql = @"
INSERT INTO files (
    project_id, name, relative_path, extension, category,
    file_size_kb, lines_of_code, char_count, complexity_score,
    hash_sha256, content, created_at, modified_at, embedding
) VALUES (
    @ProjectId, @Name, @Path, @Ext, @Category,
    @Size, @Lines, @Chars, @Complexity,
    @Hash, @Content, @Created, @Modified, @Embedding
)
"@
    
    try {
        $command = $Connection.CreateCommand()
        $command.CommandText = $sql
        
        $command.Parameters.AddWithValue("@ProjectId", $ProjectId) | Out-Null
        $command.Parameters.AddWithValue("@Name", $FileData.name) | Out-Null
        $command.Parameters.AddWithValue("@Path", $FileData.file_path) | Out-Null
        $command.Parameters.AddWithValue("@Ext", $FileData.extension) | Out-Null
        $command.Parameters.AddWithValue("@Category", $FileData.category) | Out-Null
        $command.Parameters.AddWithValue("@Size", $FileData.file_size_kb) | Out-Null
        $command.Parameters.AddWithValue("@Lines", $FileData.lines_of_code) | Out-Null
        $command.Parameters.AddWithValue("@Chars", $FileData.char_count) | Out-Null
        $command.Parameters.AddWithValue("@Complexity", $FileData.complexity_score) | Out-Null
        $command.Parameters.AddWithValue("@Hash", $FileData.hash_sha256) | Out-Null
        $command.Parameters.AddWithValue("@Content", $FileData.code.Substring(0, [Math]::Min(50000, $FileData.code.Length))) | Out-Null
        $command.Parameters.AddWithValue("@Created", $FileData.created_at) | Out-Null
        $command.Parameters.AddWithValue("@Modified", $FileData.modified_at) | Out-Null
        $command.Parameters.AddWithValue("@Embedding", ($FileData.embedding -join ",")) | Out-Null
        
        $command.ExecuteNonQuery() | Out-Null
        return $true
    } catch {
        Write-Host "⚠️ خطأ في إدراج الملف: $($_.Exception.Message)" -ForegroundColor $Colors.Warning
        return $false
    }
}

function Get-FileStats {
    param($File, [string]$Content)
    
    $stats = @{
        Lines       = ($Content | Measure-Object -Line).Lines
        Characters  = $Content.Length
        Complexity  = 0
    }
    
    # مؤشر التعقيد
    $complexity = (($Content | Select-String -Pattern @('\{', '\}', 'if\s*\(', 'for\s*\(', 'while\s*\(', 'function\s', 'class\s') -All).Count) / ([math]::Max($stats.Lines, 1))
    $stats.Complexity = [Math]::Round($complexity, 3)
    
    return $stats
}

function Extract-Keywords {
    param([string]$Content)
    
    # كلمات مفتاحية عامة
    $keywords = @(
        'function', 'class', 'interface', 'async', 'await', 'import', 'export',
        'const', 'let', 'var', 'public', 'private', 'protected', 'abstract',
        'interface', 'type', 'enum', 'decorator', 'middleware', 'controller',
        'service', 'repository', 'dto', 'entity', 'model', 'schema'
    )
    
    $found = @()
    foreach ($keyword in $keywords) {
        if ($Content -match "\b$keyword\b") {
            $found += $keyword
        }
    }
    
    return $found | Select-Object -Unique
}

function Create-JSONEmbeddings {
    param(
        [string]$OutputPath,
        [PSCustomObject[]]$Components,
        [hashtable]$Statistics
    )
    
    $embeddings = @{
        metadata = @{
            version          = "3.0"
            format          = "JSON Embeddings + Vectors"
            generated_at    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            timestamp_iso   = (Get-Date).ToUniversalTime().ToString("o")
            total_vectors   = $Components.Count
        }
        statistics = $Statistics
        components = @()
    }
    
    foreach ($component in $Components) {
        $embeddings.components += @{
            id              = $component.id
            name            = $component.name
            category        = $component.category
            embedding       = $component.embedding
            metadata        = @{
                lines           = $component.lines_of_code
                complexity      = $component.complexity_score
                size_kb         = $component.file_size_kb
                hash            = $component.hash_sha256
                keywords        = $component.keywords
            }
        }
    }
    
    $embeddings | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $OutputPath -Encoding UTF8 -Force
    Write-Host "✅ تم إنشاء: embeddings_vectors.json" -ForegroundColor $Colors.Success
}

function Create-SkillsMarkdown {
    param(
        [string]$OutputPath,
        [string]$ProjectName,
        [PSCustomObject[]]$Components,
        [hashtable]$Statistics
    )
    
    $md = @"
# 🤖 AI Skills & Knowledge Base: $ProjectName

> **تم الإنشاء:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  
> **الإصدار:** 3.0 Professional  
> **الغرض:** توثيق Skills للنماذج الذكية (LLM)

---

## 📊 الإحصائيات الرئيسية

| المقياس | القيمة |
|---------|--------|
| 🔢 إجمالي المكونات | $($Components.Count) |
| 📝 إجمالي أسطر الكود | $($Statistics.total_lines) |
| 💾 حجم المشروع | $($Statistics.total_size_mb) MB |
| ⚙️ متوسط التعقيد | $([math]::Round($Statistics.avg_complexity, 2)) |
| 📂 الفئات الفريدة | $($Statistics.unique_categories) |

---

## 🎯 Skills القابلة للاستخدام

### 1️⃣ تحليل الكود
**الوصف:** القدرة على فهم وتحليل بنية المشروع  
**الملفات المرتبطة:** $($Components.Count) ملف  
**مستوى التعقيد:** $([math]::Round($Statistics.avg_complexity, 2))

\`\`\`
- استخراج الوحدات الرئيسية
- تحديد الفئات والواجهات
- تتبع التبعيات
- حساب مؤشرات الجودة
\`\`\`

### 2️⃣ توليد التوثيق
**الوصف:** توليد وثائق شاملة من الكود  
**عدد الملفات المحللة:** $($Components.Count)

### 3️⃣ الصيانة والتحديث
**الوصف:** تحديد الأجزاء القديمة والتحديثات المطلوبة  
**آخر تحديث:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

---

## 📂 الملفات والفئات

"@
    
    $categories = $Components | Group-Object -Property category | Sort-Object Count -Descending
    
    foreach ($category in $categories) {
        $md += @"
`n### $($category.Name) ($($category.Count) ملف)`n
| الملف | الأسطر | التعقيد | الحجم |
|------|--------|---------|-------|
"@
        foreach ($file in $category.Group | Sort-Object file_path) {
            $md += "| `$($file.file_path)` | $($file.lines_of_code) | $($file.complexity_score) | $($file.file_size_kb) KB |`n"
        }
    }
    
    $md += @"
`n---

## 🔍 الكلمات المفتاحية والموضوعات

\`\`\`
الكلمات الرئيسية المستخرجة من المشروع:
"@
    
    $allKeywords = @()
    foreach ($component in $Components) {
        $allKeywords += $component.keywords
    }
    
    $topKeywords = $allKeywords | Group-Object | Sort-Object Count -Descending | Select-Object -First 20 | ForEach-Object { $_.Name }
    $md += "`n" + ($topKeywords -join ", ") + "`n\`\`\``n"
    
    $md += @"
`n---

## 📋 الملفات التفصيلية

"@
    
    foreach ($component in $Components | Sort-Object category, file_path) {
        $md += @"
`n### 📄 $($component.file_path)`n
- **الفئة:** $($component.category)  
- **الامتداد:** $($component.extension)  
- **الحجم:** $($component.file_size_kb) KB  
- **الأسطر:** $($component.lines_of_code)  
- **التعقيد:** $($component.complexity_score)  
- **آخر تعديل:** $($component.modified_at)  
- **الـ Hash:** \`$($component.hash_sha256)\`  

**محتوى:**
\`\`\`$($component.extension.TrimStart('.'))`n$($component.code.Substring(0, [Math]::Min(2000, $component.code.Length)))`n\`\`\`

"@
    }
    
    $md | Out-File -LiteralPath $OutputPath -Encoding UTF8 -Force
    Write-Host "✅ تم إنشاء: Skills_LLM.md" -ForegroundColor $Colors.Success
}

# ==================== البرنامج الرئيسي ====================

try {
    Show-Banner
    
    # 1️⃣ الحصول على المسار
    $ProjectPath = Get-ProjectPath-Safe -InputPath $ProjectPath
    if (-not $ProjectPath) {
        exit 1
    }
    
    $repoDirectory = Get-Item -LiteralPath $ProjectPath
    $repoName = $repoDirectory.Name
    
    Write-Host "📂 المشروع: $repoName" -ForegroundColor $Colors.Accent
    Write-Host "📁 المسار: $ProjectPath`n" -ForegroundColor $Colors.Info
    
    # 2️⃣ إنشاء مجلد المخرجات
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $outputDir = Join-Path $repoDirectory.Parent.FullName "$($repoName)_AI_SKILLS_$timestamp"
    
    New-Item -ItemType Directory -Path $outputDir -ErrorAction Stop | Out-Null
    Write-Host "📁 مجلد المخرجات: $outputDir`n" -ForegroundColor $Colors.Success
    
    # 3️⃣ إعدادات المعالجة
    $excludeDirs = @('.git', 'node_modules', 'bin', 'obj', 'dist', 'build', 'coverage', '.vs', '.idea', '.vscode', 'packages')
    $uiExtensions = @('.html', '.xaml', '.jsx', '.tsx', '.vue', '.razor', '.css', '.scss', '.less', '.svg', '.md', '.markdown', '.yml', '.yaml', '.json', '.txt', '.xml', '.config', '.ps1', '.py', '.js', '.ts', '.cs', '.go', '.java')
    $maxSizeBytes = $MaxFileSizeMB * 1MB
    
    Write-Host "🔍 جاري الفحص الشامل...`n" -ForegroundColor $Colors.Info
    
    # 4️⃣ جمع الملفات
    $allFiles = Get-ChildItem -LiteralPath $ProjectPath -Recurse -File -Force -ErrorAction SilentlyContinue | 
        Where-Object {
            $file = $_
            $skip = $false
            foreach ($dir in $excludeDirs) {
                if ($file.FullName -match [regex]::Escape([System.IO.Path]::DirectorySeparatorChar + $dir + [System.IO.Path]::DirectorySeparatorChar)) {
                    $skip = $true; break
                }
            }
            (-not $skip) -and ($file.Length -le $maxSizeBytes) -and ($uiExtensions -contains $file.Extension.ToLower())
        }
    
    $fileCount = @($allFiles).Count
    Write-Host "📦 تم اكتشاف $fileCount ملف`n" -ForegroundColor $Colors.Success
    
    # 5️⃣ معالجة الملفات
    $componentsList = @()
    $counter = 1
    $errors = @()
    
    foreach ($file in $allFiles) {
        try {
            $relativePath = $file.FullName.Substring($ProjectPath.Length).TrimStart('\', '/')
            $rawCode = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop
            
            if ([string]::IsNullOrWhiteSpace($rawCode)) { continue }
            
            $stats = Get-FileStats -File $file -Content $rawCode
            $fileHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            $embedding = Get-TextEmbedding -Text $rawCode
            $keywords = Extract-Keywords -Content $rawCode
            
            # تحديد الفئة
            $category = switch ($file.Extension.ToLower()) {
                ".yml"      { "YAML / CI-CD Workflow" }
                ".yaml"     { "YAML / CI-CD Workflow" }
                ".md"       { "Documentation / Markdown" }
                ".markdown" { "Documentation / Markdown" }
                ".xaml"     { "WPF / WinUI 3" }
                ".html"     { "HTML5 / Web" }
                ".jsx"      { "React JSX" }
                ".tsx"      { "React TSX" }
                ".vue"      { "Vue.js" }
                ".razor"    { "Blazor Razor" }
                ".css"      { "CSS Styles" }
                ".scss"     { "SCSS Styles" }
                ".json"     { "Configuration / JSON" }
                ".txt"      { "Plain Text" }
                ".xml"      { "XML Config" }
                ".ps1"      { "PowerShell Script" }
                ".py"       { "Python Script" }
                ".js"       { "JavaScript" }
                ".ts"       { "TypeScript" }
                ".cs"       { "C# Code" }
                ".go"       { "Go Code" }
                ".java"     { "Java Code" }
                default     { "General Code" }
            }
            
            $component = [PSCustomObject]@{
                id                = "cmp_$($repoName.ToLower())_$("{0:D5}" -f $counter)"
                name              = $file.BaseName
                file_path         = $relativePath
                category          = $category
                extension         = $file.Extension.ToLower()
                file_size_kb      = [math]::Round($file.Length / 1KB, 2)
                lines_of_code     = $stats.Lines
                char_count        = $stats.Characters
                complexity_score  = $stats.Complexity
                hash_sha256       = $fileHash
                embedding         = $embedding
                keywords          = $keywords
                code              = $rawCode.Trim()
                created_at        = $file.CreationTime.ToString("yyyy-MM-dd HH:mm:ss")
                modified_at       = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            }
            
            $componentsList += $component
            $counter++
            
            if ($counter % 10 -eq 0) {
                Write-Host "  ✔️ معالج $counter ملف..." -ForegroundColor $Colors.Info
            }
        } catch {
            $errors += "خطأ في $($file.Name): $($_.Exception.Message)"
        }
    }
    
    $processedCount = $componentsList.Count
    Write-Host "`n✅ تمت معالجة $processedCount ملف`n" -ForegroundColor $Colors.Success
    
    # 6️⃣ حساب الإحصائيات
    $statistics = @{
        total_files         = $fileCount
        processed_files     = $processedCount
        total_lines         = ($componentsList | Measure-Object -Property lines_of_code -Sum).Sum
        total_size_mb       = [math]::Round(($componentsList | Measure-Object -Property file_size_kb -Sum).Sum / 1024, 2)
        avg_complexity      = [math]::Round(($componentsList | Measure-Object -Property complexity_score -Average).Average, 3)
        unique_categories   = ($componentsList | Select-Object -Unique category).Count
        errors              = $errors.Count
    }
    
    # 7️⃣ إنشاء JSON Embeddings
    Write-Host "📊 جاري تصدير البيانات...`n" -ForegroundColor $Colors.Info
    
    $jsonPath = Join-Path $outputDir "embeddings_vectors.json"
    Create-JSONEmbeddings -OutputPath $jsonPath -Components $componentsList -Statistics $statistics
    
    # 8️⃣ إنشاء قاعدة البيانات SQLite
    $dbPath = Join-Path $outputDir "$($repoName)_project.db"
    
    # تنزيل أو استخدام System.Data.SQLite
    try {
        [System.Reflection.Assembly]::LoadWithPartialName("System.Data.SQLite") | Out-Null
        
        $connection = Connect-Database -DbPath $dbPath
        if ($connection) {
            # إنشاء الجداول
            $initSQL = Initialize-SQLiteDatabase -DbPath $dbPath -ProjectName $repoName
            
            # تنفيذ العمليات
            foreach ($sql in ($initSQL -split ';')) {
                if (-not [string]::IsNullOrWhiteSpace($sql)) {
                    Execute-SQLCommand -Connection $connection -CommandText $sql
                }
            }
            
            # إدراج المشروع
            $projectSQL = "INSERT INTO projects (name, path, total_files, total_lines, description) VALUES ('$repoName', '$ProjectPath', $processedCount, $($statistics.total_lines), 'AI Skills Database')"
            Execute-SQLCommand -Connection $connection -CommandText $projectSQL
            
            # الحصول على معرف المشروع
            $getIdSQL = "SELECT last_insert_rowid() as id"
            $command = $connection.CreateCommand()
            $command.CommandText = $getIdSQL
            $projectId = $command.ExecuteScalar()
            
            # إدراج الملفات
            foreach ($component in $componentsList) {
                Insert-FileToDatabase -Connection $connection -ProjectId $projectId -FileData $component
            }
            
            $connection.Close()
            Write-Host "✅ تم إنشاء: $($repoName)_project.db" -ForegroundColor $Colors.Success
        }
    } catch {
        Write-Host "⚠️ تنبيه: لم يتم إنشاء قاعدة البيانات - قد تكون SQLite غير مثبتة" -ForegroundColor $Colors.Warning
        Write-Host "   يمكنك تثبيتها عبر: Install-Package System.Data.SQLite -Force" -ForegroundColor $Colors.Info
    }
    
    # 9️⃣ إنشاء Skills Markdown
    $mdPath = Join-Path $outputDir "Skills_LLM.md"
    Create-SkillsMarkdown -OutputPath $mdPath -ProjectName $repoName -Components $componentsList -Statistics $statistics
    
    # 🔟 الملخص النهائي
    Write-Host "`n$(('█' * 65))" -ForegroundColor $Colors.Accent
    Write-Host "  ✨ اكتمل التحليل بنجاح!" -ForegroundColor $Colors.Success
    Write-Host "$(('█' * 65))`n" -ForegroundColor $Colors.Accent
    
    Write-Host "📁 مجلد المخرجات:" -ForegroundColor $Colors.Accent
    Write-Host "   $outputDir`n" -ForegroundColor $Colors.Info
    
    Write-Host "📋 الملفات المُنشأة:" -ForegroundColor $Colors.Accent
    Write-Host "   1️⃣  embeddings_vectors.json  → موجهات وأرقام للـ AI" -ForegroundColor $Colors.Info
    Write-Host "   2️⃣  $($repoName)_project.db       → قاعدة بيانات شاملة" -ForegroundColor $Colors.Info
    Write-Host "   3️⃣  Skills_LLM.md           → توثيق Skills للنماذج الذكية`n" -ForegroundColor $Colors.Info
    
    Write-Host "📊 الملخص الإحصائي:" -ForegroundColor $Colors.Accent
    Write-Host "   ├─ الملفات المعالجة: $processedCount" -ForegroundColor $Colors.Info
    Write-Host "   ├─ إجمالي أسطر الكود: $($statistics.total_lines)" -ForegroundColor $Colors.Info
    Write-Host "   ├─ حجم المشروع: $($statistics.total_size_mb) MB" -ForegroundColor $Colors.Info
    Write-Host "   ├─ متوسط التعقيد: $($statistics.avg_complexity)" -ForegroundColor $Colors.Info
    Write-Host "   └─ الأخطاء: $($errors.Count)`n" -ForegroundColor $(if ($errors.Count -gt 0) { $Colors.Warning } else { $Colors.Success })
    
    Write-Host "🎯 الاستخدام:" -ForegroundColor $Colors.Accent
    Write-Host "   • embeddings_vectors.json → استخدم في RAG/Vector Search" -ForegroundColor $Colors.Info
    Write-Host "   • _project.db → استعلم عن الملفات والإحصائيات" -ForegroundColor $Colors.Info
    Write-Host "   • Skills_LLM.md → علّم النماذج الذكية عن المشروع`n" -ForegroundColor $Colors.Info
    
} catch {
    Write-Host "`n❌ خطأ حرج: $($_.Exception.Message)" -ForegroundColor $Colors.Error
    exit 1
}

Read-Host "`n✅ اضغط Enter للخروج"
