function New-Splash(){
    param(
        [Parameter(Mandatory=$true)]
        [string] $ApplicationName,

        [Parameter(Mandatory=$false)]
        [string] $Title,

        [Parameter(Mandatory=$true)]
        [string] $DisplayLanguage = 'English',
        
        [Parameter(Mandatory=$false)]
        [string] $WindowState = 'Normal'
    )

  #Creates a new PowerShell runspace for the UI to run in.
    $runspace = [RunspaceFactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions = "UseNewThread"          
    $runspace.Open()

    $splash = [HashTable]::Synchronized(@{})
    $splash.Title = $Title
    $splash.ApplicationName = $ApplicationName
    $splash.DisplayLanguage = $DisplayLanguage
    $splash.WindowState = $WindowState

    #Stores the translations for the UI elements.
    $splash.LanguageText = @{
       Chinese = @("\u5B89\u88C5", "\u7ECF\u8FC7\u65F6\u95F4")
       
       Danish = @("Installation", "Forl\u00F8bet tid")
       
       Dutch = @("Installeren", "verstreken Tijd")
       
       English = @("Installing", "Elapsed Time")
       
       Finnish = @("Asennetaan", "kulunut aika")
       
       French = @("Installation", "Temps \u00C9coul\u00E9")
       
       German = @("Installation", "vergangene Zeit")
       
       Hebrew = @(".\u05DE\u05EA\u05E7\u05D9\u05DF", "\u05D6\u05DE\u05DF \u05E9\u05D7\u05DC\u05E3")
       
       Italian = @("Installazione", "Tempo Trascorso")
       
       Japanese = @("\u30A4\u30F3\u30B9\u30C8\u30FC\u30EB\u3057\u3066\u3044\u307E\u3059", "\u7D4C\u904E\u6642\u9593")
       
       Norwegian = @("Installerer", "medg\u00E5tt tid")
       
       Polish = @("Trwa instalowanie", "Czas od pocz\u0105tku")
       
       Portuguese = @("Instalando", "Tempo Decorrido")
       
       Russian = @("\u0423\u0441\u0442\u0430\u043D\u043E\u0432\u043A\u0430", "\u041F\u0440\u043E\u0448\u0435\u0434\u0448\u0435\u0435 \u0432\u0440\u0435\u043C\u044F")
       
       Spanish = @("Instalando", "Tiempo Transcurrido")
       
       Swedish = @("Installerar", "F\u00F6rfluten tid")
       
       Turkish = @("Y\u00FCkleme", "ge\u00E7en Zaman")
       
       Ukrainian = @("\u0423\u0441\u0442\u0430\u043D\u043E\u0432\u043B\u0435\u043D\u043D\u044F", "\u043C\u0438\u043D\u0443\u043B\u0438\u0439 \u0447\u0430\u0441")
    }


    $runspace.SessionStateProxy.SetVariable("app", $splash)
    $splashScript = [PowerShell]::Create().AddScript({
	    Add-Type -Assembly PresentationFramework
        Add-Type -Assembly PresentationCore
        Add-Type -Assembly WindowsBase
        Add-Type -Assembly mscorlib
        Add-Type -Assembly System.Core
	    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="$($app.Title)" WindowStartupLocation="CenterScreen" MinWidth="850" MinHeight="650" ResizeMode="CanResize" WindowState="$($app.WindowState)" WindowStyle="None" Topmost="False" Background="White" ShowInTaskbar="False">
    <Grid Background="#e5e6e6">
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="*" />
    </Grid.ColumnDefinitions>
    <Grid.RowDefinitions>
      <RowDefinition Height="192" />
      <RowDefinition Height="*" />
      <RowDefinition Height="192" />
    </Grid.RowDefinitions>
      <TextBlock FontSize="24" Margin="48 0 0 0" Grid.Row="0" 
        VerticalAlignment="Center" Foreground="#367C2B">$($app.ApplicationName)</TextBlock>
      <Border BorderBrush="#333" BorderThickness="0 1 0 1" Grid.Row="1">
        <DockPanel HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Background="White">
          <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
            <TextBlock Name="SplashTitle" FontSize="24" Margin="2">$(($app.LanguageText).($app.DisplayLanguage)[0])</TextBlock>
            <ProgressBar IsIndeterminate="True" Height="24" Width="400" />
            <TextBlock Name="ElapsedTime" HorizontalAlignment="Center" Text="Elapsed Time" />
          </StackPanel>
        </DockPanel>
      </Border>
      <TextBlock FontSize="24" Margin="48 0 0 0" VerticalAlignment="Center"
        HorizontalAlignment="Left" Grid.Row="2" Foreground="#367C2B">Enterprise Desktop Services</TextBlock>
      <Image Name="LogoImage" Margin="0 0 48 0" Width="232" Height="73" HorizontalAlignment="Right" Grid.Row="2"></Image>
    </Grid>
</Window>
"@
        #Logo encoded as Base64 string:
        $app.Base64Logo = @"
iVBORw0KGgoAAAANSUhEUgAAAOgAAABJCAMAAAAAN5oBAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAYBQTFRFr8kv5O3kKnkyc6cx
apxp5+gsd6V3+vz6PJU56/Lra5csutG6pcSl//UrytzKL3wy//sqJmoryNQrQ5o5tM20Flcp0NstHWUs3OjcMYEz0+LS8fbxQIA+2OAshK2GWoRoQ4JB9fIr
8ewrw9fCLIQ2mLUsWZJbX50z2eXZnb6cqL0rLXQrgrg1XYUnNYg1RXMm9fj1WKQ4OY02lrwxO306TYlLh6Qpi7KKI14rVY5TPINKfJ6GxdnFMHUtMI05R3hY
wtcvlq4pLHMrlLiTMmonncAwkreRR4RFOHo2KXAtS4pbZJpworyoaqJzcZd9XqBnvs/CKnUvM3cySoZIUItPOoIyLHQr1uPXlbOdirMvi7iQao52lr2bnrik
MGxEW5IvImkzL5U8rcOyzt/O4OArIHExvc4s6u8sP45Ij62XLXMrUI4wc6JyTH4qv9S+j7SOfqp+YZZh4OrfyNrHb59umbuY3ubgl6+d+PYr0tzUz9vRfZ0p
r8qvxtXJmL+e////x1G+/AAAAIB0Uk5T////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////wA4BUtnAAAJKklEQVR42uyai1faWB7HA0lEBCXI
WwQJIijxgQiKbUN9A22nUx7K0JmOWkRnrmgBbddd3cm/Pr97b4LocWdoz57u0c33tMhNwk0+9/ckgVH+T8TooDqoDqqD6qA6qA6qg+qgOqgOqoPqoDqoDvq/
Ak2Y69b3Az9Gf8OK/th675w2m54cqLn+xw+/RZIxlp3dBi3V2Njpru3VgLWaeEqg9V+ikSS7vcaHw+ET/ugogN+EA0xt32Z7be08FdDJH57tsse8yK9tz7KL
DscgyBFja4w7LAa294vPWtUnAVp/drrNi4GlmGM+G8kODmaz2WQ2Ox+JRHynLMOLbha1/U8B9P1uQGRiADafdSxmHQx7iE2aTCbnIz6bcZcdvZo6mHwCoOZX
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
TkSuQmCC
"@

        #Convert the Base64 encoded logo in to a bitmap:
        $app.BinaryLogo = [Convert]::FromBase64String($app.Base64Logo)
        $app.BitmapLogo = New-Object System.Windows.Media.Imaging.BitmapImage
        $app.BitmapLogo.BeginInit()
        $app.BitmapLogo.StreamSource = New-Object System.IO.MemoryStream (,$app.BinaryLogo)
        $app.BitmapLogo.EndInit()

        #Create the Window and setup the Control References
        $reader = (New-Object System.Xml.XmlNodeReader $xaml)
        $app.Window = [Windows.Markup.XamlReader]::Load( $reader )
        $app.TimeLabel = $app.window.FindName("ElapsedTime")
        $app.TitleLabel = $app.window.FindName("SplashTitle")
        $app.LogoImage = $app.window.FindName("LogoImage")
        $app.LogoImage.Source = $app.BitmapLogo #Set the logo image

        #Setup the Elapsed Time Timer and Event:
        $app.StopWatch = [system.diagnostics.stopwatch]::StartNew()
        $app.TimerAction = { $app.TimeLabel.Text = [string]::Format("$(($app.LanguageText).($app.DisplayLanguage)[1]): {0:00}:{1:00}:{2:00}", `
                $app.StopWatch.Elapsed.Hours, `
                $app.StopWatch.Elapsed.Minutes, `
                $app.StopWatch.Elapsed.Seconds) }

        $app.Window.Add_SourceInitialized({
            $app.Timer = New-Object System.Windows.Threading.DispatcherTimer
            $app.Timer.Interval = [TimeSpan]"0:0:0.5"
            $app.Timer.Add_Tick($app.TimerAction)
            $app.Timer.Start()
        })

        #Allow Drag
        $app.Window.Add_MouseLeftButtonDown({
            $_.Handled = $true
            $app.Window.DragMove()
        })

        &$app.TimerAction #Run the timer action
        $app.Window.ShowDialog() | Out-Null
        $app.Error = $Error
    })

    $splashScript.Runspace = $runspace
    $data = $splashScript.BeginInvoke()

    $i = 0
    while (-not($splash.Window.IsVisible) -and ($i -lt 60000)) {
      $i++
      Start-Sleep -Milliseconds 200
    }

    return $splash
}

function Set-SplashTitle(){
    param(
        [Parameter(Mandatory=$true)]
        [HashTable] $Splash,
        [Parameter(Mandatory=$true)]
        [string] $Title
    )
    $Splash.Window.Dispatcher.Invoke("Normal", [action]{ $Splash.TitleLabel.Text = $Title})
}

function Stop-Splash(){
    param(
        [Parameter(Mandatory=$true)]
        [HashTable] $Splash
    )

    $Splash.Window.Dispatcher.invoke("Normal", [action]{ $Splash.Window.Close() })
}

<#Unit Test Area:
$splash = New-Splash -Title "Unit Test Splash Screen" -ApplicationName "Unit Test Application"
start-sleep 3
Set-SplashTitle -Splash $splash -Title "Title Logo Unit Test Change"
start-sleep 30
Stop-Splash -Splash $splash#>
