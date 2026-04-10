-- Alternative implementation using hs.canvas for true click-through

local obj = {}

-- Create a canvas-based trail that's truly click-through
function obj.createCanvasTrail(config)
    -- Calculate bounding box of all screens
    local allScreens = hs.screen.allScreens()
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    
    for _, screen in ipairs(allScreens) do
        local frame = screen:fullFrame()
        minX = math.min(minX, frame.x)
        minY = math.min(minY, frame.y)
        maxX = math.max(maxX, frame.x + frame.w)
        maxY = math.max(maxY, frame.y + frame.h)
    end
    
    local canvasFrame = {
        x = minX,
        y = minY,
        w = maxX - minX,
        h = maxY - minY
    }
    
    -- Create canvas
    local canvas = hs.canvas.new(canvasFrame)
    
    -- Make it click-through
    canvas:level(hs.canvas.windowLevels.overlay)
    canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces + 
                    hs.canvas.windowBehaviors.stationary)
    canvas:clickActivating(false)
    canvas:canvasMouseEvents(false)  -- This is key - no mouse events!
    canvas:alpha(1.0)
    
    -- Trail points storage
    local points = {}
    local maxPoints = config.maxPoints or 50
    local fadeTime = config.fadeTime or 0.5
    
    -- Catmull-Rom spline function
    local function catmullRomSpline(p0, p1, p2, p3, t)
        local v0 = (p2.x - p0.x) * 0.5
        local v1 = (p3.x - p1.x) * 0.5
        
        local a0 = 2*p1.x - 2*p2.x + v0 + v1
        local a1 = -3*p1.x + 3*p2.x - 2*v0 - v1
        local a2 = v0
        local a3 = p1.x
        
        local x = a0*t*t*t + a1*t*t + a2*t + a3
        
        v0 = (p2.y - p0.y) * 0.5
        v1 = (p3.y - p1.y) * 0.5
        
        a0 = 2*p1.y - 2*p2.y + v0 + v1
        a1 = -3*p1.y + 3*p2.y - 2*v0 - v1
        a2 = v0
        a3 = p1.y
        
        local y = a0*t*t*t + a1*t*t + a2*t + a3
        
        return {x = x - canvasFrame.x, y = y - canvasFrame.y}
    end
    
    -- Update function
    local function updateCanvas()
        canvas:replaceElements()  -- Clear canvas
        
        local now = hs.timer.secondsSinceEpoch()
        
        -- Remove old points
        while #points > 0 and (now - points[1].time) > fadeTime do
            table.remove(points, 1)
        end
        
        if #points >= 4 then
            -- Draw smooth curve through points
            for i = 1, #points - 3 do
                local p0 = points[i]
                local p1 = points[i + 1]
                local p2 = points[i + 2]
                local p3 = points[i + 3]
                
                -- Build path segments
                local pathSegments = {}
                for t = 0, 1, 0.1 do
                    local pt = catmullRomSpline(p0, p1, p2, p3, t)
                    table.insert(pathSegments, pt)
                end
                
                -- Calculate fade
                local age = now - p1.time
                local alpha = math.max(0, 1 - age / fadeTime)
                local position = i / #points
                local width = config.baseWidth + (config.maxWidth - config.baseWidth) * (1 - position)
                
                -- Draw segments
                for j = 1, #pathSegments - 1 do
                    canvas:appendElements({
                        type = "segments",
                        action = "stroke",
                        strokeColor = {
                            red = config.color.red,
                            green = config.color.green,
                            blue = config.color.blue,
                            alpha = config.color.alpha * alpha
                        },
                        strokeWidth = width * alpha,
                        strokeCapStyle = "round",
                        strokeJoinStyle = "round",
                        coordinates = {pathSegments[j], pathSegments[j + 1]}
                    })
                end
            end
        end
    end
    
    -- Timer for smooth animation
    local updateTimer = hs.timer.doEvery(0.016, updateCanvas)  -- 60fps
    
    -- Add point function
    local function addPoint(x, y)
        local point = {
            x = x,
            y = y,
            time = hs.timer.secondsSinceEpoch()
        }
        table.insert(points, point)
        
        if #points > maxPoints then
            table.remove(points, 1)
        end
    end
    
    -- Show canvas
    canvas:show()
    
    return {
        canvas = canvas,
        addPoint = addPoint,
        stop = function()
            updateTimer:stop()
            canvas:delete()
        end
    }
end

return obj